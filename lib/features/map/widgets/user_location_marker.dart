import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';

class UserLocationMarker extends StatefulWidget {
  final LatLng location;
  final double heading;

  const UserLocationMarker({
    super.key,
    required this.location,
    this.heading = 0.0,
  });

  @override
  State<UserLocationMarker> createState() => _UserLocationMarkerState();
}

class _UserLocationMarkerState extends State<UserLocationMarker>
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
                  // Accuracy ring
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.success.withOpacity(0.15),
                      border: Border.all(
                        color: AppTheme.success.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                  ),
                  // Arrow dot
                  Transform.rotate(
                    angle: widget.heading * (3.14159 / 180),
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
                      color: AppTheme.primary.withOpacity(0.4),
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
