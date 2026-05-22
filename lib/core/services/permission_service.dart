import 'package:permission_handler/permission_handler.dart';
import '../services/logger_service.dart';

enum PermissionStatus {
  granted,
  denied,
  permanentlyDenied,
}

class PermissionService {
  /// Request all permissions needed for Phase 1: location only.
  /// BLE permissions are handled separately in Phase 3.
  Future<PermissionStatus> requestLocationPermissions() async {
    // Check current status first
    final status = await Permission.locationWhenInUse.status;

    if (status.isGranted) return PermissionStatus.granted;
    if (status.isPermanentlyDenied) return PermissionStatus.permanentlyDenied;

    // Request
    final result = await Permission.locationWhenInUse.request();
    if (result.isGranted) return PermissionStatus.granted;
    if (result.isPermanentlyDenied) return PermissionStatus.permanentlyDenied;

    return PermissionStatus.denied;
  }

  /// Request background location — needed for Phase 6 navigation background service.
  Future<PermissionStatus> requestBackgroundLocationPermission() async {
    // Must have foreground location first
    final foreground = await requestLocationPermissions();
    if (foreground != PermissionStatus.granted) return foreground;

    final status = await Permission.locationAlways.status;
    if (status.isGranted) return PermissionStatus.granted;
    if (status.isPermanentlyDenied) return PermissionStatus.permanentlyDenied;

    final result = await Permission.locationAlways.request();
    if (result.isGranted) return PermissionStatus.granted;
    if (result.isPermanentlyDenied) return PermissionStatus.permanentlyDenied;

    return PermissionStatus.denied;
  }

  /// Request POST_NOTIFICATIONS — Android 13+
  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    final result = await Permission.notification.request();
    return result.isGranted;
  }

  /// Check location permission without requesting.
  Future<bool> isLocationGranted() async {
    return await Permission.locationWhenInUse.isGranted;
  }

  /// Open app settings — use when permanently denied.
  Future<void> openSettings() async {
    await openAppSettings();
    appLogger.i('Opened app settings for permission management');
  }
}
