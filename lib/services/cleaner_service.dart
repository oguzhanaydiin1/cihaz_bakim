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
}
