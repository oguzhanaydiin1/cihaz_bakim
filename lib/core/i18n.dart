import 'dart:io';

/// Uygulamanın dil seçeneği. [system] Windows/Android dilini izler.
enum AppLanguage { system, tr, en }

/// Basit iki dilli metin desteği.
///
/// Her metin yazıldığı yerde iki dilde verilir: `L.t('Kaldır', 'Uninstall')`.
/// Böylece Türkçe ve İngilizce yan yana durur, değişkenli metinler de doğal yazılır:
/// `L.t('$n dosya silindi.', '$n files deleted.')`.
class L {
  static bool _tr = _systemIsTr();

  static bool get isTr => _tr;

  /// Sunucuya ve web bağlantılarına iletilen dil kodu.
  static String get code => _tr ? 'tr' : 'en';

  static void apply(AppLanguage language) {
    _tr = switch (language) {
      AppLanguage.tr => true,
      AppLanguage.en => false,
      AppLanguage.system => _systemIsTr(),
    };
  }

  static bool _systemIsTr() {
    try {
      return Platform.localeName.toLowerCase().startsWith('tr');
    } catch (_) {
      return false;
    }
  }

  static String t(String tr, String en) => _tr ? tr : en;

  /// Ayrı iş parçacıklarında (isolate) üretilen aşama adları her zaman Türkçe gelir;
  /// arayüzde burada çevrilir.
  static String phase(String phase) {
    if (_tr) return phase;
    return _phases[phase] ?? phase;
  }

  static const _phases = {
    'Ölçülüyor': 'Measuring',
    'Siliniyor': 'Deleting',
    'Dosyalar listeleniyor': 'Listing files',
    'Karşılaştırılıyor': 'Comparing',
    'Fotoğraflar aranıyor': 'Looking for photos',
    'Küçültülüyor': 'Compressing',
    'Fotoğraflar inceleniyor': 'Checking photos',
    'Konum siliniyor': 'Removing location',
    'Geri Dönüşüm Kutusu okunuyor': 'Reading the Recycle Bin',
    'Orijinaller Geri Dönüşüm Kutusu’na taşınıyor': 'Moving originals to the Recycle Bin',
  };
}
