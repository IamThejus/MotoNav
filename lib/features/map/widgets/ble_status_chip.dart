import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

enum BleConnectionState { connected, disconnected, connecting }

class BleStatusChip extends StatelessWidget {
  final BleConnectionState connectionState;
  final VoidCallback? onTap;

  const BleStatusChip({
    super.key,
    required this.connectionState,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (connectionState) {
      BleConnectionState.connected => (
          AppTheme.bleConnected,
          'Connected',
          Icons.bluetooth_connected_rounded,
        ),
      BleConnectionState.disconnected => (
          AppTheme.bleDisconnected,
          'Disconnected',
          Icons.bluetooth_disabled_rounded,
        ),
      BleConnectionState.connecting => (
          AppTheme.primary,
          'Connecting...',
          Icons.bluetooth_searching_rounded,
        ),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
