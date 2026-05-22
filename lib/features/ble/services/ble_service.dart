import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/logger_service.dart';

class BleService {
  static const _prefKeyDeviceId = 'ble_last_device_id';

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  /// Connects to [device], discovers services, and returns the target characteristic.
  Future<BluetoothCharacteristic> connect(BluetoothDevice device) async {
    await device.connect(
      timeout: const Duration(seconds: 10),
      autoConnect: false,
    );

    // Request larger MTU so packets up to ~512 bytes fit in one write
    try {
      await device.requestMtu(512);
    } catch (_) {}

    final services = await device.discoverServices();
    for (final service in services) {
      if (_uuidMatch(service.uuid.str, AppConstants.bleServiceUuid)) {
        for (final char in service.characteristics) {
          if (_uuidMatch(char.uuid.str, AppConstants.bleCharUuid)) {
            appLogger.i('BLE: Found characteristic ${char.uuid.str}');
            return char;
          }
        }
      }
    }

    await device.disconnect();
    throw Exception('MotoNav service/characteristic not found on this device');
  }

  Future<void> disconnect(BluetoothDevice device) async {
    await device.disconnect();
  }

  Future<void> writePacket(BluetoothCharacteristic char, Uint8List data) async {
    final withoutResponse = char.properties.writeWithoutResponse;
    await char.write(data, withoutResponse: withoutResponse);
  }

  Future<void> saveDeviceId(String remoteId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyDeviceId, remoteId);
  }

  Future<void> clearDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyDeviceId);
  }

  Future<String?> getSavedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyDeviceId);
  }

  bool _uuidMatch(String a, String b) => a.toLowerCase() == b.toLowerCase();

  void dispose() {}
}
