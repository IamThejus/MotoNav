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
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _scaleAnim = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _navigateToMap() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MapScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for map state — navigate once ready or on error
    ref.listen<MapState>(mapProvider, (_, state) {
      if (state.status == MapStatus.ready ||
          state.status == MapStatus.locationDenied ||
          state.status == MapStatus.locationPermanentlyDenied) {
        // Small delay to let splash animation complete
        Future.delayed(const Duration(milliseconds: 600), _navigateToMap);
      }
    });

    final mapState = ref.watch(mapProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          return FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceCard,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primary.withOpacity(0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.15),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.navigation_rounded,
                        color: AppTheme.primary,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'MotoNav',
                      style: TextStyle(
                        color: AppTheme.onSurface,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ESP32 Navigation Companion',
                      style: TextStyle(
                        color: AppTheme.onSurfaceMuted,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 56),
                    // Status
                    _buildStatusIndicator(mapState.status),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusIndicator(MapStatus status) {
    final (message, showSpinner) = switch (status) {
      MapStatus.idle || MapStatus.locating => ('Getting location...', true),
      MapStatus.ready => ('Ready', false),
      MapStatus.locationDenied => ('Location permission needed', false),
      MapStatus.locationPermanentlyDenied => ('Permission denied', false),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSpinner)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppTheme.primary),
            ),
          )
        else
          const Icon(Icons.check_circle_outline_rounded,
              color: AppTheme.success, size: 14),
        const SizedBox(width: 8),
        Text(
          message,
          style: const TextStyle(
            color: AppTheme.onSurfaceMuted,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
