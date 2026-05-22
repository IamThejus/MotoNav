import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/ble_provider.dart';

class BleScreen extends ConsumerStatefulWidget {
  const BleScreen({super.key});

  @override
  ConsumerState<BleScreen> createState() => _BleScreenState();
}

class _BleScreenState extends ConsumerState<BleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bleState = ref.read(bleProvider);
      if (!bleState.isConnected && !bleState.isScanning && !bleState.isConnecting) {
        ref.read(bleProvider.notifier).startScan();
      }
    });
  }

  @override
  void dispose() {
    ref.read(bleProvider.notifier).stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleProvider);

    final namedResults = bleState.scanResults
        .where((r) => r.device.platformName.isNotEmpty)
        .toList()
      ..sort((a, b) {
        final aIsTarget = a.device.platformName == AppConstants.bleDeviceName;
        final bIsTarget = b.device.platformName == AppConstants.bleDeviceName;
        if (aIsTarget && !bIsTarget) return -1;
        if (!aIsTarget && bIsTarget) return 1;
        return a.device.platformName.compareTo(b.device.platformName);
      });

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('ESP32 Display'),
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connected device card
          if (bleState.isConnected) ...[
            _ConnectedCard(
              name: bleState.connectedDeviceName ?? 'MotoNav',
              deviceId: bleState.connectedDeviceId ?? '',
              onDisconnect: () => ref.read(bleProvider.notifier).disconnect(),
            ),
            const SizedBox(height: 20),
          ],

          // Connecting indicator
          if (bleState.isConnecting) ...[
            const _ConnectingCard(),
            const SizedBox(height: 20),
          ],

          // Error banner
          if (bleState.status == BleStatus.error && bleState.errorMessage != null)
            _ErrorBanner(message: bleState.errorMessage!),

          // Scan controls
          Row(
            children: [
              const Text(
                'Nearby Devices',
                style: TextStyle(
                  color: AppTheme.onSurfaceMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (bleState.isScanning)
                TextButton.icon(
                  onPressed: () => ref.read(bleProvider.notifier).stopScan(),
                  icon: const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                  label: const Text('Stop', style: TextStyle(color: AppTheme.primary)),
                )
              else
                TextButton.icon(
                  onPressed: bleState.isConnecting
                      ? null
                      : () => ref.read(bleProvider.notifier).startScan(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Scan'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Device list
          if (namedResults.isEmpty && !bleState.isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No devices found.\nMake sure MotoNav is powered on.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 14),
                ),
              ),
            )
          else
            ...namedResults.map(
              (result) => _DeviceTile(
                result: result,
                isConnecting: bleState.isConnecting,
                onTap: () => ref.read(bleProvider.notifier).connect(result.device),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _ConnectedCard extends StatelessWidget {
  final String name;
  final String deviceId;
  final VoidCallback onDisconnect;

  const _ConnectedCard({
    required this.name,
    required this.deviceId,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bleConnected.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.bleConnected.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected_rounded,
              color: AppTheme.bleConnected, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppTheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  deviceId,
                  style: const TextStyle(
                    color: AppTheme.onSurfaceMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onDisconnect,
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}

class _ConnectingCard extends StatelessWidget {
  const _ConnectingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
          SizedBox(width: 12),
          Text(
            'Connecting...',
            style: TextStyle(
              color: AppTheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppTheme.error, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final ScanResult result;
  final bool isConnecting;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.result,
    required this.isConnecting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName;
    final isMotoNav = name == AppConstants.bleDeviceName;
    final rssi = result.rssi;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: isMotoNav
            ? Border.all(color: AppTheme.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          isMotoNav
              ? Icons.bluetooth_rounded
              : Icons.devices_rounded,
          color: isMotoNav ? AppTheme.primary : AppTheme.onSurfaceMuted,
          size: 22,
        ),
        title: Text(
          name,
          style: TextStyle(
            color: isMotoNav ? AppTheme.primary : AppTheme.onSurface,
            fontSize: 14,
            fontWeight: isMotoNav ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: Text(
          result.device.remoteId.str,
          style: const TextStyle(
            color: AppTheme.onSurfaceMuted,
            fontSize: 11,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$rssi dBm',
              style: const TextStyle(
                color: AppTheme.onSurfaceMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.onSurfaceMuted, size: 18),
          ],
        ),
        onTap: isConnecting ? null : onTap,
      ),
    );
  }
}
