import 'dart:math' as math;

import '../core/i18n.dart';
import '../models/models.dart';
import 'cleaner_service.dart';
import 'isolate_runner.dart';

/// Android (ve geliştirme sırasında diğer platformlar) için örnek veri.
///
/// Android'de gerçek tarama sonraki adımda platform kanalı + MediaStore ile yazılacak.
/// Not: Android 8'den beri başka uygulamaların önbelleği silinemez; bu yüzden
/// Android kategorileri yalnızca uygulamanın erişebildiği dosyalardan oluşur.
class SampleCleaner extends CleanerService {
  static const _mb = 1024 * 1024;
  static const _gb = 1024 * _mb;

  final _removed = <String>{};

  @override
  bool get isSample => true;

  @override
  bool get supportsStartup => false;

  @override
  String get deleteDestination => L.t('Silinecek', 'will be deleted');

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
      StorageInfo(total: 128 * _gb, free: 24 * _gb, label: L.t('dahili depolama dolu', 'internal storage used'));

  @override
  Future<bool> isAdmin() async => false;

  @override
  Future<bool> relaunchAsAdmin() async => false;

  @override
  Future<List<JunkCategory>?> scanJunk({ProgressReporter? onProgress, CancelToken? token}) async {
    if (!await _simulate('Ölçülüyor', onProgress, token)) return null;
    final all = [
      JunkCategory(id: 'apk', name: L.t('Kurulum dosyaları (APK)', 'Install files (APK)'), description: L.t('İndirilenler’de kalan kurulum dosyaları', 'Install files left in Downloads'), sizeBytes: 640 * _mb),
      JunkCategory(
        id: 'olddl',
        name: L.t('Eski indirmeler', 'Old downloads'),
        description: L.t('90 günden eski, açılmamış dosyalar', 'Unopened files older than 90 days'),
        sizeBytes: 1220 * _mb,
        warning: L.t('Gözden geçirin', 'Review'),
        selected: false,
      ),
      JunkCategory(id: 'empty', name: L.t('Boş klasörler', 'Empty folders'), description: L.t('İçinde dosya kalmamış klasörler', 'Folders with no files left'), sizeBytes: 4096),
      JunkCategory(
        id: 'wa',
        name: L.t('WhatsApp medyası', 'WhatsApp media'),
        description: L.t('Gönderilen videolar ve sesli mesajlar (izinle)', 'Sent videos and voice messages (with permission)'),
        sizeBytes: 2100 * _mb,
        warning: L.t('Gözden geçirin', 'Review'),
        selected: false,
      ),
      JunkCategory(id: 'thumbs', name: L.t('Küçük resim dosyaları', 'Thumbnail files'), description: L.t('.thumbnails klasörü', '.thumbnails folder'), sizeBytes: 180 * _mb),
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

  // ---- Uygulama kaldırıcı ----

  final _uninstalled = <String>{};

  @override
  Future<List<InstalledApp>> installedApps() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final now = DateTime.now();
    final all = [
      InstalledApp(name: 'Oyun Merkezi', uninstallCommand: '-', registryKey: 'a', publisher: 'Örnek Yayıncı', version: '3.2', installDate: now.subtract(const Duration(days: 420)), sizeBytes: 1800 * _mb),
      InstalledApp(name: 'Fotoğraf Düzenleyici', uninstallCommand: '-', registryKey: 'b', publisher: 'Örnek Stüdyo', version: '12.0', installDate: now.subtract(const Duration(days: 90)), sizeBytes: 640 * _mb),
      InstalledApp(name: 'Not Defteri Pro', uninstallCommand: '-', registryKey: 'c', publisher: 'Örnek Yazılım', version: '1.4', installDate: now.subtract(const Duration(days: 12)), sizeBytes: 45 * _mb),
    ];
    return all.where((a) => !_uninstalled.contains(a.registryKey)).toList();
  }

  @override
  Future<String?> runUninstaller(InstalledApp app) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _uninstalled.add(app.registryKey);
    return null;
  }

  @override
  bool isSafeLeftover(String path) => false;

  @override
  Future<bool> recycleFolder(String path) async => false;

  // ---- Pil ve sağlık ----

  @override
  Future<BatteryInfo?> batteryInfo() async => const BatteryInfo(
        name: 'Örnek pil',
        designCapacity: 4500,
        fullChargeCapacity: 3870,
        cycleCount: 312,
        chemistry: 'Li-ion',
      );

  @override
  Future<List<DiskHealth>> diskHealth() async => const [
        DiskHealth(name: 'Dahili depolama', mediaType: 'SSD', busType: 'UFS', status: 'Healthy', sizeBytes: 128 * _gb),
      ];

  @override
  Future<void> openBatteryReport() async {}

  // ---- Fotoğraflar ----

  @override
  String defaultPicturesFolder() => '/storage/emulated/0/DCIM';

  @override
  Future<List<PhotoFile>?> findPhotos(String root, {int minSize = 1024 * 1024, ProgressReporter? onProgress, CancelToken? token}) async {
    if (!await _simulate('Fotoğraflar aranıyor', onProgress, token)) return null;
    return [
      for (var i = 0; i < 6; i++) PhotoFile(path: 'DCIM/Camera/IMG_2024${1001 + i}.jpg', sizeBytes: (8 - i) * _mb),
    ];
  }

  @override
  Future<CompressResult?> compressPhotos(
    List<String> paths,
    CompressOptions options, {
    ProgressReporter? onProgress,
    CancelToken? token,
  }) async {
    if (!await _simulate('Küçültülüyor', onProgress, token)) return null;
    return CompressResult(compressed: paths.length, skipped: 0, failed: 0, savedBytes: paths.length * 3 * _mb, donePaths: paths);
  }

  @override
  Future<List<GpsPhoto>?> findLocationPhotos(String root, {ProgressReporter? onProgress, CancelToken? token}) async {
    if (!await _simulate('Fotoğraflar inceleniyor', onProgress, token)) return null;
    return [
      GpsPhoto(path: 'DCIM/Camera/IMG_20240812.jpg', latitude: 41.0151, longitude: 28.9795),
      GpsPhoto(path: 'DCIM/Camera/IMG_20240901.jpg', latitude: 38.4237, longitude: 27.1428),
    ];
  }

  @override
  Future<(int, int)> removeLocation(List<String> paths, {ProgressReporter? onProgress}) async {
    await _simulate('Konum siliniyor', onProgress, null);
    return (paths.length, 0);
  }

  // ---- Sistem bilgisi ----

  @override
  Future<SystemInfo?> systemInfo() async => SystemInfo(
        cpuName: 'Örnek 8 çekirdekli işlemci',
        cores: 8,
        threads: 8,
        maxMhz: 2800,
        totalRam: 8 * _gb,
        osName: 'Android',
        osBuild: '-',
        gpus: const [GpuInfo(name: 'Örnek grafik birimi', memoryBytes: 0)],
        bootTime: DateTime.now().subtract(const Duration(hours: 31, minutes: 12)),
        manufacturer: 'Örnek',
        model: 'Telefon',
      );

  @override
  Stream<LiveStats> liveStats() {
    var t = 0;
    return Stream<LiveStats>.periodic(const Duration(milliseconds: 1500), (_) {
      t++;
      double wave(double base, double amp, double speed) => base + amp * math.sin(t * speed);
      return LiveStats(
        cpuPercent: wave(28, 18, 0.7).clamp(0.0, 100.0),
        cpuMhz: wave(2100, 500, 0.5).round(),
        ramAvailable: (wave(3.2, 0.4, 0.2) * _gb).round(),
        gpuPercent: wave(12, 10, 0.9).clamp(0.0, 100.0),
        diskRead: (wave(4, 4, 1.1) * _mb).round(),
        diskWrite: (wave(2, 2, 0.8) * _mb).round(),
        netDown: (wave(1.5, 1.4, 0.6) * _mb).round(),
        netUp: (wave(0.3, 0.25, 0.4) * _mb).round(),
        temperature: wave(38, 3, 0.3),
        topMemory: const [
          ProcessMemory(name: 'Tarayıcı', bytes: 1400 * _mb, count: 12),
          ProcessMemory(name: 'Mesajlaşma', bytes: 520 * _mb, count: 3),
          ProcessMemory(name: 'Sistem', bytes: 380 * _mb, count: 1),
        ],
      );
    });
  }

  // ---- İzin kontrolü ----

  @override
  Future<PermissionOverview?> permissions() async {
    final now = DateTime.now();
    return PermissionOverview(
      enabled: const {PermissionKind.camera: true, PermissionKind.microphone: true, PermissionKind.location: true},
      uses: [
        PermissionUse(kind: PermissionKind.camera, appName: 'Kamera', detail: 'com.example.camera', storeApp: true, allowed: true, lastUsed: now.subtract(const Duration(hours: 2))),
        PermissionUse(kind: PermissionKind.microphone, appName: 'Mesajlaşma', detail: 'com.example.chat', storeApp: true, allowed: true, inUse: true, lastUsed: now),
        PermissionUse(kind: PermissionKind.location, appName: 'Harita', detail: 'com.example.maps', storeApp: true, allowed: true, lastUsed: now.subtract(const Duration(days: 1))),
      ],
    );
  }

  @override
  Future<void> openPrivacySettings(PermissionKind kind) async {}

  // ---- Genel ----

  @override
  Future<void> openUrl(String url) async {}

  @override
  String? get errorLogPath => null;
}
