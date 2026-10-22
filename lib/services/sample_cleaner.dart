import '../models/models.dart';
import 'cleaner_service.dart';
import 'isolate_runner.dart';

/// Android (ve geliştirme sırasında diğer platformlar) için örnek veri.
///
/// Android'de gerçek tarama sonraki adımda platform kanalı + MediaStore ile yazılacak.
/// Not: Android 8'den beri başka uygulamaların önbelleği silinemez; bu yüzden
/// Android kategorileri yalnızca uygulamanın erişebildiği dosyalardan oluşur.
class SampleCleaner implements CleanerService {
  static const _mb = 1024 * 1024;
  static const _gb = 1024 * _mb;

  final _removed = <String>{};

  @override
  bool get isSample => true;

  @override
  bool get supportsStartup => false;

  @override
  String get deleteDestination => 'Silinecek';

  @override
  String? get settingsPath => null;

  @override
  String? get legacySettingsPath => null;

  /// İlerleme çubuğunu denemek için yapay bekleme. İptal edilirse false döner.
  Future<bool> _simulate(String phase, ProgressReporter? onProgress, CancelToken? token) async {
    for (var i = 1; i <= 12; i++) {
      if (token?.isCancelled ?? false) return false;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      onProgress?.call(ScanProgress(
        phase: phase,
        files: i * 137,
        bytes: i * 45 * _mb,
        current: '/storage/emulated/0/DCIM/Camera',
      ));
    }
    return !(token?.isCancelled ?? false);
  }

  @override
  Future<StorageInfo?> storageInfo() async =>
      const StorageInfo(total: 128 * _gb, free: 24 * _gb, label: 'dahili depolama dolu');

  @override
  Future<bool> isAdmin() async => false;

  @override
  Future<bool> relaunchAsAdmin() async => false;

  @override
  Future<List<JunkCategory>?> scanJunk({ProgressReporter? onProgress, CancelToken? token}) async {
    if (!await _simulate('Ölçülüyor', onProgress, token)) return null;
    final all = [
      JunkCategory(id: 'apk', name: 'Kurulum dosyaları (APK)', description: 'İndirilenler’de kalan kurulum dosyaları', sizeBytes: 640 * _mb),
      JunkCategory(
        id: 'olddl',
        name: 'Eski indirmeler',
        description: '90 günden eski, açılmamış dosyalar',
        sizeBytes: 1220 * _mb,
        warning: 'Gözden geçirin',
        selected: false,
      ),
      JunkCategory(id: 'empty', name: 'Boş klasörler', description: 'İçinde dosya kalmamış klasörler', sizeBytes: 4096),
      JunkCategory(
        id: 'wa',
        name: 'WhatsApp medyası',
        description: 'Gönderilen videolar ve sesli mesajlar (izinle)',
        sizeBytes: 2100 * _mb,
        warning: 'Gözden geçirin',
        selected: false,
      ),
      JunkCategory(id: 'thumbs', name: 'Küçük resim dosyaları', description: '.thumbnails klasörü', sizeBytes: 180 * _mb),
    ];
    return all.where((c) => !_removed.contains(c.id)).toList();
  }

  @override
  Future<CleanResult> cleanJunk(List<JunkCategory> categories, {ProgressReporter? onProgress}) async {
    await _simulate('Siliniyor', onProgress, null);
    _removed.addAll(categories.map((c) => c.id));
    return CleanResult(freedBytes: categories.fold<int>(0, (s, c) => s + c.sizeBytes), skippedFiles: 0);
  }

  @override
  List<String> defaultUserFolders() => ['DCIM', 'Pictures', 'Download', 'WhatsApp/Media'];

  @override
  Future<List<DuplicateGroup>?> findDuplicates(
    List<String> roots, {
    required int minSize,
    List<String> excluded = const [],
    ProgressReporter? onProgress,
    CancelToken? token,
  }) async {
    if (!await _simulate('Karşılaştırılıyor', onProgress, token)) return null;
    final now = DateTime.now();
    DuplicateGroup g(int size, List<String> paths) {
      final files = [
        for (var i = 0; i < paths.length; i++)
          DuplicateFile(path: paths[i], modified: now.subtract(Duration(days: 30 - i))),
      ];
      return DuplicateGroup(size: size, files: files)..keepOnly(files.first);
    }

    return [
      g(240 * _mb, ['DCIM/Camera/VID_20240901.mp4', 'Download/VID_20240901.mp4']),
      g(4 * _mb, ['DCIM/Camera/IMG_20240812.jpg', 'WhatsApp/Media/Images/IMG-20240812-WA0003.jpg']),
      g(1 * _mb, [
        'Pictures/Screenshots/Screenshot_0412.png',
        'Download/Screenshot_0412.png',
        'Telegram/Images/Screenshot_0412.png',
      ]),
    ];
  }

  @override
  Future<int> deleteFiles(List<String> paths) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return paths.length;
  }

  @override
  String defaultUsageRoot() => '/storage/emulated/0';

  @override
  Future<List<FolderUsage>?> folderUsage(String root, {ProgressReporter? onProgress, CancelToken? token}) async {
    if (!await _simulate('Ölçülüyor', onProgress, token)) return null;
    FolderUsage u(String name, int gb) => FolderUsage(name: name, path: root, bytes: gb * _gb, isDir: false);
    return [
      u('Fotoğraflar', 34),
      u('Uygulamalar', 28),
      u('WhatsApp', 19),
      u('Sistem', 14),
      u('Videolar', 11),
      u('İndirilenler', 6),
      u('Diğer', 5),
    ];
  }

  @override
  Future<List<StartupItem>> startupItems() async => [];

  @override
  Future<String?> setStartupEnabled(StartupItem item, bool enabled) async => 'Bu platformda desteklenmiyor.';

  @override
  Future<void> revealInExplorer(String path) async {}
}
