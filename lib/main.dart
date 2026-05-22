import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/home/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait — landscape navigation comes later if needed
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Edge-to-edge dark UI
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  runApp(
    const ProviderScope(
      child: MotoNavApp(),
    ),
  );
}

class MotoNavApp extends StatelessWidget {
  const MotoNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MotoNav',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashScreen(),
    );
  }
}
