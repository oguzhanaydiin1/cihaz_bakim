import 'package:flutter/material.dart';

/// Tema değişince artar; uygulama kökü bunu dinleyip bütün arayüzü yeniden çizer.
final themeTick = ValueNotifier<int>(0);

/// [mode] ('light' | 'dark' | 'system') ve sistemin parlaklığına göre [AppColors.dark]'ı ayarlar.
void applyThemeMode(String mode) {
  final was = AppColors.dark;
  AppColors.dark = mode == 'system'
      ? WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
      : mode == 'dark';
  if (was != AppColors.dark) themeTick.value++;
}

class AppColors {
  /// Koyu tema açık mı? Açılışta ve tema değişince AppState ayarlar.
  static bool dark = false;
  static Color _r(int light, int darkValue) => Color(dark ? darkValue : light);

  static Color get accent => _r(0xFF1D4ED8, 0xFF60A5FA);
  static Color get onAccent => _r(0xFFFFFFFF, 0xFF0B1220);
  static Color get background => _r(0xFFF4F5F7, 0xFF0B0F19);
  static Color get surface => _r(0xFFFFFFFF, 0xFF141A26);
  static Color get line => _r(0xFFE5E7EB, 0xFF263041);
  static Color get border2 => _r(0xFFD1D5DB, 0xFF374151);
  static Color get divider => _r(0xFFF0F1F3, 0xFF1E2533);
  static Color get text => _r(0xFF111827, 0xFFE5E7EB);
  static Color get muted => _r(0xFF4B5563, 0xFF9CA3AF);
  static Color get nav => _r(0xFF0F172A, 0xFF080C16);
  static Color get navItem => _r(0xFF1E293B, 0xFF141B2B);
  static Color get navItemActive => _r(0xFF334155, 0xFF26324A);
  static Color get navText => _r(0xFFCBD5E1, 0xFFCBD5E1);
  static Color get navLabel => _r(0xFF94A3B8, 0xFF94A3B8);
  static Color get brand => _r(0xFF60A5FA, 0xFF60A5FA);
  static Color get warnBg => _r(0xFFFFF7ED, 0xFF2B1B0E);
  static Color get warnText => _r(0xFF9A3412, 0xFFFDBA74);
  static Color get keepBg => _r(0xFFECFDF5, 0xFF0C2A20);
  static Color get keepText => _r(0xFF065F46, 0xFF6EE7B7);
  static Color get groupHead => _r(0xFFF9FAFB, 0xFF18202E);
  static Color get tagBg => _r(0xFFF3F4F6, 0xFF1F2937);
  static Color get tagText => _r(0xFF374151, 0xFFD1D5DB);
  static Color get dangerBg => _r(0xFFFEE2E2, 0xFF3B1517);
  static Color get dangerText => _r(0xFFB91C1C, 0xFFFCA5A5);
  static Color get infoBg => _r(0xFFEFF4FF, 0xFF15213F);
  static Color get infoText => _r(0xFF1E3A8A, 0xFFBFDBFE);
  static Color get sealAccent => _r(0xFFC97A16, 0xFFF2A541);
  static Color get chartFill => _r(0x1F1D4ED8, 0x3360A5FA);

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
    brightness: AppColors.dark ? Brightness.dark : Brightness.light,
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    surface: AppColors.surface,
    onSurface: AppColors.text,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: AppColors.dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(18)),
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
        side: BorderSide(color: AppColors.border2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    dividerTheme: DividerThemeData(color: AppColors.divider, space: 1, thickness: 1),
  );
}
