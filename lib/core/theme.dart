import 'package:flutter/material.dart';

class AppColors {
  static const accent = Color(0xFF1D4ED8);
  static const background = Color(0xFFF4F5F7);
  static const line = Color(0xFFE5E7EB);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF4B5563);
  static const nav = Color(0xFF0F172A);
  static const navItem = Color(0xFF1E293B);
  static const navText = Color(0xFFCBD5E1);
  static const navLabel = Color(0xFF94A3B8);
  static const brand = Color(0xFF60A5FA);
  static const warnBg = Color(0xFFFFF7ED);
  static const warnText = Color(0xFF9A3412);
  static const keepBg = Color(0xFFECFDF5);
  static const keepText = Color(0xFF065F46);
  static const groupHead = Color(0xFFF9FAFB);

  /// Disk haritası kutuları için renkler.
  static const map = [
    Color(0xFF1D4ED8),
    Color(0xFF0F766E),
    Color(0xFF7C3AED),
    Color(0xFFB45309),
    Color(0xFFBE185D),
    Color(0xFF0369A1),
    Color(0xFF4D7C0F),
    Color(0xFF475569),
  ];
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    cardTheme: const CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: AppColors.text,
        side: const BorderSide(color: Color(0xFFD1D5DB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFF0F1F3), space: 1, thickness: 1),
  );
}
