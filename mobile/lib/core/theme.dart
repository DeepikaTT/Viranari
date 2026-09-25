import 'package:flutter/material.dart';

abstract final class ViraColors {
  static const background = Color(0xFFFFF9FC);
  static const surface = Color(0xFFFFFFFF);
  static const plum = Color(0xFF40223D);
  static const mutedPlum = Color(0xFF76506F);
  static const lilac = Color(0xFFF0E2F1);
  static const lilacStrong = Color(0xFFD8BDDD);
  static const pink = Color(0xFFE94378);
  static const pinkDark = Color(0xFFC9275E);
  static const success = Color(0xFF267A5A);
  static const successSoft = Color(0xFFE4F4EC);
  static const warning = Color(0xFFB86A16);
  static const dangerSoft = Color(0xFFFFE5EC);
}

ThemeData buildViraTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ViraColors.plum,
    brightness: Brightness.light,
    surface: ViraColors.surface,
  ).copyWith(
    primary: ViraColors.plum,
    secondary: ViraColors.pink,
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
