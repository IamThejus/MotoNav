import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/logger_service.dart';
import '../services/ble_service.dart';

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// BLE state
// ---------------------------------------------------------------------------

enum BleStatus { idle, scanning, connecting, connected, disconnected, error }

class BleState {
  final BleStatus status;
  final String? connectedDeviceName;
  final String? connectedDeviceId;
  final List<ScanResult> scanResults;
  final String? errorMessage;

  const BleState({
    this.status = BleStatus.idle,
    this.connectedDeviceName,
    this.connectedDeviceId,
    this.scanResults = const [],
    this.errorMessage,
  });

  bool get isConnected => status == BleStatus.connected;
  bool get isScanning => status == BleStatus.scanning;
  bool get isConnecting => status == BleStatus.connecting;

  BleState copyWith({
    BleStatus? status,
    String? connectedDeviceName,
    String? connectedDeviceId,
    List<ScanResult>? scanResults,
    String? errorMessage,
    bool clearConnectedDevice = false,
    bool clearError = false,
  }) {
    return BleState(
      status: status ?? this.status,
      connectedDeviceName: clearConnectedDevice
          ? null
          : (connectedDeviceName ?? this.connectedDeviceName),
      connectedDeviceId: clearConnectedDevice
          ? null
          : (connectedDeviceId ?? this.connectedDeviceId),
      scanResults: scanResults ?? this.scanResults,
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ---------------------------------------------------------------------------
// BLE notifier
// ---------------------------------------------------------------------------

class BleNotifier extends StateNotifier<BleState> {
  final BleService _service;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _char;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  BleNotifier(this._service) : super(const BleState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (!mounted) return;
      if (adapterState != BluetoothAdapterState.on) {
        state = state.copyWith(
          status: BleStatus.idle,
          errorMessage: 'Bluetooth is off',
        );
        return;
      }
      await _tryAutoReconnect();
    } catch (e) {
      appLogger.w('BLE: Init error: $e');
    }
  }

  Future<void> _tryAutoReconnect() async {
    final savedId = await _service.getSavedDeviceId();
    if (savedId == null || !mounted) return;

    appLogger.i('BLE: Auto-reconnecting to $savedId');
    state = state.copyWith(status: BleStatus.connecting);

    try {
      final device = BluetoothDevice.fromId(savedId);
      await _doConnect(device);
    } catch (e) {
      if (mounted) {
        appLogger.w('BLE: Auto-reconnect failed: $e');
        state = state.copyWith(
          status: BleStatus.disconnected,
          clearConnectedDevice: true,
        );
      }
    }
  }

  Future<void> startScan() async {
    if (!mounted || state.isScanning) return;

    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (!mounted) return;
      if (adapterState != BluetoothAdapterState.on) {
        state = state.copyWith(
          status: BleStatus.error,
          errorMessage: 'Bluetooth is off. Enable it and try again.',
        );
        return;
      }
    } catch (e) {
      return;
    }

    await _scanSub?.cancel();
    _scanSub = null;
    state = state.copyWith(
      status: BleStatus.scanning,
      scanResults: [],
      clearError: true,
    );

    await _service.startScan();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) state = state.copyWith(scanResults: results);
    });

    // Revert status when scan finishes (via timeout or stopScan)
    FlutterBluePlus.isScanning.where((s) => !s).first.then((_) {
      if (mounted && state.isScanning) {
        _scanSub?.cancel();
        _scanSub = null;
        state = state.copyWith(
          status: state.isConnected ? BleStatus.connected : BleStatus.idle,
        );
      }
    });
  }

  Future<void> stopScan() async {
    await _service.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    if (mounted && state.isScanning) {
      state = state.copyWith(
        status: state.isConnected ? BleStatus.connected : BleStatus.idle,
      );
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    if (!mounted || state.isConnecting || state.isConnected) return;
    if (state.isScanning) await stopScan();

    state = state.copyWith(status: BleStatus.connecting, clearError: true);
    try {
      await _doConnect(device);
    } catch (e) {
      if (mounted) {
        appLogger.e('BLE: Connection failed', error: e);
        state = state.copyWith(
          status: BleStatus.error,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
          clearConnectedDevice: true,
        );
      }
    }
  }

  Future<void> _doConnect(BluetoothDevice device) async {
    _char = await _service.connect(device);
    if (!mounted) {
      await _service.disconnect(device);
      return;
    }

    _device = device;
    await _service.saveDeviceId(device.remoteId.str);

    final name = device.platformName.isNotEmpty ? device.platformName : 'MotoNav';
    state = state.copyWith(
      status: BleStatus.connected,
      connectedDeviceName: name,
      connectedDeviceId: device.remoteId.str,
    );
    appLogger.i('BLE: Connected to $name (${device.remoteId.str})');

    await _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen((cs) {
      if (cs == BluetoothConnectionState.disconnected && mounted) {
        _onDeviceDisconnected();
      }
    });
  }

  void _onDeviceDisconnected() {
    appLogger.w('BLE: Device disconnected');
    _connectionSub?.cancel();
    _connectionSub = null;
    _char = null;
    _device = null;
    if (mounted) {
      state = state.copyWith(
        status: BleStatus.disconnected,
        clearConnectedDevice: true,
      );
    }
  }

  Future<void> disconnect() async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    final device = _device;
    _char = null;
    _device = null;

    if (device != null) {
      try {
        await _service.disconnect(device);
      } catch (_) {}
    }
    await _service.clearDeviceId();

    if (mounted) {
      state = state.copyWith(
        status: BleStatus.idle,
        clearConnectedDevice: true,
      );
    }
  }

  Future<void> writePacket(Uint8List data) async {
    final char = _char;
    if (char == null) return;
    try {
      await _service.writePacket(char, data);
    } catch (e) {
      appLogger.e('BLE: write failed', error: e);
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final bleProvider = StateNotifierProvider<BleNotifier, BleState>((ref) {
  return BleNotifier(ref.watch(bleServiceProvider));
});
