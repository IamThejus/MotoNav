import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------------
  // Brand colors
  // ---------------------------------------------------------------------------
  static const Color primary = Color(0xFFFFCC00);       // Yellow — route highlight
  static const Color surface = Color(0xFF0E0E0F);        // Near-black surface
  static const Color surfaceElevated = Color(0xFF1A1A1C);
  static const Color surfaceCard = Color(0xFF232325);
  static const Color onSurface = Color(0xFFEEEEEE);
  static const Color onSurfaceMuted = Color(0xFF888888);
  static const Color error = Color(0xFFFF4444);
  static const Color success = Color(0xFF00E676);
  static const Color bleConnected = Color(0xFF00E676);
  static const Color bleDisconnected = Color(0xFFFF4444);
  static const Color routeColor = Color(0xFFFFCC00);
  static const Color roadMinor = Color(0xFF3A3A3C);
  static const Color roadMain = Color(0xFF5A5A5E);

  // ---------------------------------------------------------------------------
  // ThemeData
  // ---------------------------------------------------------------------------
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        surface: surface,
        onSurface: onSurface,
        error: error,
      ),
      scaffoldBackgroundColor: surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: onSurfaceMuted, fontSize: 15),
        prefixIconColor: onSurfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: onSurface, size: 22),
      dividerTheme: const DividerThemeData(
        color: surfaceElevated,
        thickness: 1,
      ),
    );
  }
}
