import 'package:flutter/material.dart';

abstract final class ViraColors {
  // Final ViraNari brand direction: deep teal + lotus pink + antique gold.
  static const background = Color(0xFFFFF9F0);
  static const surface = Color(0xFFFFFCF7);
  static const plum = Color(0xFF073F42); // kept name for v0.1 source compatibility
  static const mutedPlum = Color(0xFF506869);
  static const lilac = Color(0xFFF8ECEE);
  static const lilacStrong = Color(0xFFE9C9D0);
  static const pink = Color(0xFFD95D83);
  static const pinkDark = Color(0xFFD93645);
  static const gold = Color(0xFFC9963B);
  static const success = Color(0xFF23845D);
  static const successSoft = Color(0xFFE5F4EC);
  static const warning = Color(0xFFB56B18);
  static const dangerSoft = Color(0xFFFFE7EB);
  static const midnight = Color(0xFF052E31);
}

ThemeData buildViraTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ViraColors.plum,
    brightness: Brightness.light,
    surface: ViraColors.surface,
  ).copyWith(
    primary: ViraColors.plum,
    secondary: ViraColors.pink,
    tertiary: ViraColors.gold,
    error: ViraColors.pinkDark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: ViraColors.background,
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: ViraColors.surface,
    ),
    appBarTheme: const AppBarTheme(
      surfaceTintColor: Colors.transparent,
      foregroundColor: ViraColors.plum,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ViraColors.surface,
      indicatorColor: ViraColors.lilacStrong,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ViraColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: ViraColors.lilacStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: ViraColors.plum, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
  );
}
