import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/map_provider.dart';

class UserLocationMarker extends ConsumerStatefulWidget {
  final LatLng location;
  /// True when the map is in heading-up mode (map has been rotated so the
  /// direction of travel is already at the top of the screen).  In that case
  /// the arrow must stay at 0° (screen-up) — the map rotation already handles
  /// orientation. In north-up mode (false) the arrow rotates by the compass
  /// heading so it points toward the direction of travel.
  final bool isHeadingUpMode;

  const UserLocationMarker({
    super.key,
    required this.location,
    this.isHeadingUpMode = false,
  });

  @override
  ConsumerState<UserLocationMarker> createState() => _UserLocationMarkerState();
}

class _UserLocationMarkerState extends ConsumerState<UserLocationMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Must be here (not inside AnimatedBuilder.builder) so Riverpod registers
    // the dependency on UserLocationMarker's own element and rebuilds it
    // whenever headingProvider emits — not on AnimatedBuilder's animation ticks.
    //
    // Watch unconditionally so the provider is guaranteed to stay alive even
    // when the marker doesn't use the value (heading-up mode).  Without this,
    // toggling into heading-up mode would drop UserLocationMarker's dependency
    // and the StreamProvider could be torn down, starving map_screen's listen.
    final compassDeg = ref.watch(headingProvider).valueOrNull ?? 0.0;

    // In heading-up mode the map has already been rotated so the direction of
    // travel points to the top of the screen; the arrow should stay screen-up
    // (0 rad) to avoid double-rotating.  In north-up mode the arrow rotates
    // by the compass heading so it points toward the direction of travel.
    final headingRad =
        widget.isHeadingUpMode ? 0.0 : compassDeg * (3.14159 / 180);

    return MarkerLayer(
      markers: [
        Marker(
          point: widget.location,
          width: 60,
          height: 60,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Pulse ring
                  Opacity(
                    opacity: (1.0 - _pulseAnimation.value) * 0.6,
                    child: Container(
                      width: 60 * _pulseAnimation.value,
                      height: 60 * _pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.success,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  // Compass cone — visual indicator of phone orientation.
                  // Rotates with compass on screen, independent of map rotation.
                  // Shown only during nav, when the direction-of-travel arrow
                  // is locked at 0° and otherwise gives no rotation feedback.
                  if (widget.isHeadingUpMode)
                    Transform.rotate(
                      angle: compassDeg * (math.pi / 180),
                      child: CustomPaint(
                        size: const Size(60, 60),
                        painter: _CompassConePainter(),
                      ),
                    ),
                  // Accuracy ring
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.success.withValues(alpha: 0.15),
                      border: Border.all(
                        color: AppTheme.success.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                  ),
                  // Arrow — rotated by heading captured above in build()
                  Transform.rotate(
                    angle: headingRad,
                    child: CustomPaint(
                      size: const Size(16, 16),
                      painter: _ArrowPainter(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.success
      ..style = PaintingStyle.fill;

    final path = ui.Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.7)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pie-slice "headlight" cone fanning out from the user position toward the
/// top of the canvas.  Drawn unrotated; the caller wraps it in a
/// Transform.rotate to point it in the compass direction.
class _CompassConePainter extends CustomPainter {
  // 60° angular spread, centered on the top (12 o'clock).
  static const _spread = math.pi / 3;
  // Flutter canvas: 0 rad = 3 o'clock, sweeps clockwise.
  // -π/2 = 12 o'clock; subtract half the spread to center the cone there.
  static const _startAngle = -math.pi / 2 - _spread / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          AppTheme.success.withValues(alpha: 0.55),
          AppTheme.success.withValues(alpha: 0.0),
        ],
      )
      ..style = PaintingStyle.fill;

    final path = ui.Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        _spread,
        false,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Destination pin marker
class DestinationMarker extends StatelessWidget {
  final LatLng location;

  const DestinationMarker({super.key, required this.location});

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: [
        Marker(
          point: location,
          width: 40,
          height: 48,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  color: Colors.black,
                  size: 18,
                ),
              ),
              Container(
                width: 2,
                height: 12,
                color: AppTheme.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
