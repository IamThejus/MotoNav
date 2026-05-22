import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../map/models/map_state.dart';
import '../map/providers/map_provider.dart';
import '../map/screens/map_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final AnimationController _ringCtrl;

  // Staggered entry animations driven by Interval curves
  late final Animation<double> _glowOpacity;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleOffset;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _statusOpacity;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Slow continuous rotation for the outer orbit ring
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _glowOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.00, 0.35, curve: Curves.easeOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.10, 0.50, curve: Curves.easeOut),
      ),
    );
    _logoScale = Tween<double>(begin: 0.70, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.10, 0.50, curve: Curves.easeOutBack),
      ),
    );
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.42, 0.68, curve: Curves.easeOut),
      ),
    );
    _titleOffset = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.42, 0.68, curve: Curves.easeOut),
      ),
    );
    _subtitleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.60, 0.82, curve: Curves.easeOut),
      ),
    );
    _statusOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.75, 1.00, curve: Curves.easeOut),
      ),
    );

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  void _navigateToMap() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MapScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MapState>(mapProvider, (_, state) {
      if (state.status == MapStatus.ready ||
          state.status == MapStatus.locationDenied ||
          state.status == MapStatus.locationPermanentlyDenied) {
        Future.delayed(const Duration(milliseconds: 600), _navigateToMap);
      }
    });

    final mapState = ref.watch(mapProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      body: AnimatedBuilder(
        animation: Listenable.merge([_entryCtrl, _ringCtrl]),
        builder: (context, _) => _buildBody(mapState),
      ),
    );
  }

  Widget _buildBody(MapState mapState) {
    return Column(
      children: [
        const Spacer(flex: 2),
        _buildLogoSection(),
        const SizedBox(height: 44),
        _buildTextSection(),
        const Spacer(flex: 3),
        _buildStatusSection(mapState.status),
        const SizedBox(height: 52),
      ],
    );
  }

  Widget _buildLogoSection() {
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Yellow glow halo behind logo
            Opacity(
              opacity: _glowOpacity.value,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD400).withValues(alpha: 0.20),
                      blurRadius: 80,
                      spreadRadius: 28,
                    ),
                    BoxShadow(
                      color: const Color(0xFFFFD400).withValues(alpha: 0.08),
                      blurRadius: 130,
                      spreadRadius: 60,
                    ),
                  ],
                ),
              ),
            ),

            // Outer orbit ring — rotates slowly, distinct from logo's own ring
            Opacity(
              opacity: (_glowOpacity.value * 0.55).clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: _ringCtrl.value * 2 * pi,
                child: CustomPaint(
                  size: const Size(200, 200),
                  painter: _OrbitRingPainter(),
                ),
              ),
            ),

            // Logo PNG — fades + scales in
            Opacity(
              opacity: _logoOpacity.value,
              child: Transform.scale(
                scale: _logoScale.value,
                child: Image.asset(
                  'assets/icons/motonav_logo.png',
                  width: 155,
                  height: 155,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextSection() {
    return Column(
      children: [
        FadeTransition(
          opacity: _titleOpacity,
          child: SlideTransition(
            position: _titleOffset,
            child: const Text(
              'MotoNav',
              style: TextStyle(
                color: Color(0xFFEEEEEE),
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: 4.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Opacity(
          opacity: _subtitleOpacity.value,
          child: const Text(
            'ESP32 Navigation Companion',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 12,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSection(MapStatus status) {
    final (message, isLoading) = switch (status) {
      MapStatus.idle || MapStatus.locating => ('Getting location...', true),
      MapStatus.ready => ('Ready', false),
      MapStatus.locationDenied => ('Location permission needed', false),
      MapStatus.locationPermanentlyDenied => ('Permission denied', false),
    };

    return Opacity(
      opacity: _statusOpacity.value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation(Color(0xFFFFD400)),
              ),
            )
          else
            const Icon(
              Icons.check_circle_outline_rounded,
              color: AppTheme.success,
              size: 13,
            ),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF555555),
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// Decorative outer ring with 5 arc segments, mimicking the logo's dashed ring.
// Rotates slowly via the ring AnimationController.
class _OrbitRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    final paint = Paint()
      ..color = const Color(0xFFFFD400)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    // 5 segments × 45° + 5 gaps × 27° = 225° + 135° = 360°
    const segSweep = 45.0 * pi / 180;
    const gapSweep = 27.0 * pi / 180;

    for (int i = 0; i < 5; i++) {
      final startAngle = i * (segSweep + gapSweep);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitRingPainter old) => false;
}
