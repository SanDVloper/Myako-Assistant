import 'package:flutter/material.dart';

/// Material 3 Dark (default) & Light themes optimized for Xiaomi Redmi A2
/// (solid high-contrast surfaces, 1px borders, zero BackdropFilter blur).
class AppTheme {
  AppTheme._();

  static const Color darkScaffold = Color(0xFF0F1419);
  static const Color darkSurface = Color(0xFF182028);
  static const Color darkSurfaceAlt = Color(0xFF1F2933);
  static const Color darkBorder = Color(0xFF283442);
  static const Color darkPrimary = Color(0xFF10B981);
  static const Color darkSecondary = Color(0xFF38BDF8);

  static const Color lightScaffold = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF1F5F9);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightPrimary = Color(0xFF059669);
  static const Color lightSecondary = Color(0xFF0284C7);

  /// Curated color tags for courses.
  static const List<String> coursePaletteHexes = [
    '#10B981', // Emerald
    '#38BDF8', // Sky
    '#A78BFA', // Violet
    '#F59E0B', // Amber
    '#F43F5E', // Rose
    '#14B8A6', // Teal
    '#FB923C', // Orange
    '#60A5FA', // Blue
  ];

  /// Safely parses a `#RRGGBB` hex string into a [Color].
  static Color parseHexColor(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final parsed = int.tryParse('FF$cleaned', radix: 16);
      if (parsed != null) return Color(parsed);
    }
    return darkPrimary;
  }

  static ThemeData get darkTheme => _buildTheme(isDark: true);

  static ThemeData get lightTheme => _buildTheme(isDark: false);

  static ThemeData _buildTheme({required bool isDark}) {
    final scaffold = isDark ? darkScaffold : lightScaffold;
    final surface = isDark ? darkSurface : lightSurface;
    final surfaceAlt = isDark ? darkSurfaceAlt : lightSurfaceAlt;
    final border = isDark ? darkBorder : lightBorder;
    final primary = isDark ? darkPrimary : lightPrimary;
    final secondary = isDark ? darkSecondary : lightSecondary;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: primary,
      secondary: secondary,
      surface: surface,
      surfaceContainerHighest: surfaceAlt,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: isDark ? const Color(0xFF06281E) : Colors.white,
        elevation: 1,
      ),
    );
  }
}
