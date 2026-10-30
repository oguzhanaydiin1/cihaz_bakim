/// Uygulama, geliştirici ve destek bilgileri.
/// "İletişim ve Destek" ile "Hakkında" ekranlarında gösterilir.
class AppInfo {
  /// pubspec.yaml'daki sürümle aynı olmalı (otomatik kontrol bunu denetler).
  static const version = '0.2.2';

  static const name = 'Harrier Cleaner';
  static const company = 'OA Labs';
  static const developer = 'Oğuzhan Aydın';
  static const email = 'destek@oalabs.dev';
  static const website = 'https://oalabs.dev/';
  static const privacyTr = 'https://oalabs.dev/gizlilik/#harrier';
  static const privacyEn = 'https://oalabs.dev/gizlilik/#harrier-en';
  static const copyrightYear = 2026;

  /// Yeni sürüm bilgisi (sürüm numarası, notlar, kurulum dosyası adresi ve özeti).
  static const updateManifest = 'https://oalabs.dev/harrier/latest.json';

  /// Hata raporlarının gönderildiği adres.
  static const reportEndpoint = 'https://api.oalabs.dev/v1/report';

  /// Sunucudaki uygulama kimliği.
  static const appId = 'harrier';
}
