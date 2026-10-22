import 'dart:io';

import '../models/models.dart';
import 'isolate_runner.dart';
import 'sample_cleaner.dart';
import 'windows_cleaner.dart';

/// Platforma özel tarama ve temizleme işlemleri.
/// Windows'ta gerçek işlem yapar; diğer platformlarda (şimdilik) örnek veri döndürür.
///
/// Uzun süren işlemler [CancelToken] ile iptal edilebilir; iptal edilirse null döner.
abstract class CleanerService {
  static CleanerService create() => Platform.isWindows ? WindowsCleaner() : SampleCleaner();

  /// true ise gösterilen veriler örnektir.
  bool get isSample;

  /// Başlangıç programları modülü destekleniyor mu?
  bool get supportsStartup;

  /// Silinen dosyalar nereye gidiyor? (Ekranda gösterilir.)
  String get deleteDestination;

  /// Ayar dosyasının yolu. null ise ayarlar kaydedilmez.
  String? get settingsPath;

  /// Eski sürümün ayar dosyası. Yeni dosya yoksa ayarlar buradan taşınır.
  String? get legacySettingsPath;

  Future<StorageInfo?> storageInfo();

  Future<bool> isAdmin();

  /// Uygulamayı yönetici izniyle yeniden açar. Başarılı olursa bu örnek kapanır.
  Future<bool> relaunchAsAdmin();

  Future<List<JunkCategory>?> scanJunk({ProgressReporter? onProgress, CancelToken? token});
  Future<CleanResult> cleanJunk(List<JunkCategory> categories, {ProgressReporter? onProgress});

  List<String> defaultUserFolders();
  Future<List<DuplicateGroup>?> findDuplicates(
    List<String> roots, {
    required int minSize,
    List<String> excluded = const [],
    ProgressReporter? onProgress,
    CancelToken? token,
  });

  /// Dosyaları siler (Windows'ta Geri Dönüşüm Kutusu'na taşır). Silinen dosya sayısını döndürür.
  Future<int> deleteFiles(List<String> paths);

  String defaultUsageRoot();
  Future<List<FolderUsage>?> folderUsage(String root, {ProgressReporter? onProgress, CancelToken? token});

  Future<List<StartupItem>> startupItems();

  /// Başarılıysa null, değilse kullanıcıya gösterilecek hata mesajı döndürür.
  Future<String?> setStartupEnabled(StartupItem item, bool enabled);

  /// Dosyayı Dosya Gezgini'nde seçili olarak gösterir.
  Future<void> revealInExplorer(String path);

  // ---- Uygulama kaldırıcı ----

  Future<List<InstalledApp>> installedApps();

  /// Programın kendi kaldırıcısını başlatır ve bitmesini bekler.
  /// Başarılıysa null, değilse hata mesajı döndürür.
  Future<String?> runUninstaller(InstalledApp app);

  /// Kaldırma sonrası kalan bir klasör güvenle silinebilir mi?
  /// (Program Files, AppData gibi ana klasörler asla silinmez.)
  bool isSafeLeftover(String path);

  /// Klasörü Geri Dönüşüm Kutusu'na taşır.
  Future<bool> recycleFolder(String path);

  // ---- Pil ve sağlık ----

  /// Pil yoksa (masaüstü bilgisayar) null.
  Future<BatteryInfo?> batteryInfo();
  Future<List<DiskHealth>> diskHealth();

  /// Windows'un ayrıntılı pil raporunu tarayıcıda açar.
  Future<void> openBatteryReport();

  // ---- Fotoğraflar ----

  String defaultPicturesFolder();
  Future<List<PhotoFile>?> findPhotos(String root, {int minSize = 1024 * 1024, ProgressReporter? onProgress, CancelToken? token});
  Future<CompressResult?> compressPhotos(
    List<String> paths,
    CompressOptions options, {
    ProgressReporter? onProgress,
    CancelToken? token,
  });
  Future<List<GpsPhoto>?> findLocationPhotos(String root, {ProgressReporter? onProgress, CancelToken? token});

  /// (temizlenen, başarısız)
  Future<(int, int)> removeLocation(List<String> paths, {ProgressReporter? onProgress});
}
