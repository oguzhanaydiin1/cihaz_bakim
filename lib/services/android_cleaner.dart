import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../models/models.dart';
import 'cleaner_service.dart';
import 'exif_gps.dart';
import 'isolate_runner.dart';
import 'media_utils.dart';

/// Android'de tarama ve temizleme.
///
/// Android, uygulamaların başka uygulamaların dosyalarına klasör klasör erişmesine izin vermez.
/// Bu yüzden her şey MediaStore (fotoğraf, video, müzik kütüphanesi) üzerinden yapılır; asıl iş
/// android/app/src/main/kotlin/.../MainActivity.kt içindedir ve "harrier/android" kanalıyla çağrılır.
///
/// Silme, çöp kutusuna taşıma ve değiştirme işlemlerinde Android (11 ve üstü) kullanıcıya kendi
/// onay penceresini gösterir. Kopyalar ve küçültülen fotoğrafların orijinalleri çöp kutusuna
/// taşınır (30 gün içinde geri alınabilir); gereksiz dosyalar kalıcı silinir.
class AndroidCleaner extends CleanerService {
  AndroidCleaner._(this._filesDir);

  static const _ch = MethodChannel('harrier/android');
  static const storageRoot = '/storage/emulated/0';

  static Future<AndroidCleaner> create() async {
    var dir = '';
    try {
      dir = await _ch.invokeMethod<String>('filesDir') ?? '';
    } catch (_) {}
    return AndroidCleaner._(dir);
  }

  final String _filesDir;

  /// Ekranda gösterilen yol ("DCIM/Camera/IMG_1.jpg") → dosyanın bilgisi ve adresi.
  final _media = <String, _Media>{};

  /// Gereksiz dosya kategorisi → içindeki dosyaların adresleri.
  final _junkUris = <String, List<String>>{};

  // ---------------------------------------------------------------------------
  // Genel
  // ---------------------------------------------------------------------------

  @override
  bool get isSample => false;

  @override
  bool get needsMediaPermission => true;

  @override
  bool get supportsStartup => false;

  @override
  String get deleteDestination =>
      L.t('Çöp kutusuna taşınacak (30 gün içinde geri alınabilir)', 'Will be moved to the trash (restorable for 30 days)');

  @override
  String? get settingsPath => _filesDir.isEmpty ? null : '$_filesDir/settings.json';

  @override
  String? get legacySettingsPath => null;

  @override
  String? get errorLogPath => _filesDir.isEmpty ? null : '$_filesDir/errors.log';

  @override
  Future<MediaAccess> mediaAccess({bool request = false}) async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('mediaPermission', {'request': request});
      return MediaAccess(
        granted: m?['granted'] == true,
        partial: m?['partial'] == true,
        location: m?['location'] == true,
      );
    } catch (_) {
      return const MediaAccess(granted: false, location: false);
    }
  }

  Future<bool> _ensureMedia() async {
    final now = await mediaAccess();
    if (now.granted) return true;
    return (await mediaAccess(request: true)).granted;
  }

  @override
  String rootLabel(String root) => switch (root) {
        'images' => L.t('Fotoğraflar', 'Photos'),
        'video' => L.t('Videolar', 'Videos'),
        'audio' => L.t('Müzik ve ses', 'Music & audio'),
        _ => root,
      };

  @override
  Future<StorageInfo?> storageInfo() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('storage');
      if (m == null) return null;
      return StorageInfo(
        total: (m['total'] as num).toInt(),
        free: (m['free'] as num).toInt(),
        label: L.t('dahili depolama dolu', 'of storage used'),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isAdmin() async => false;

  @override
  Future<bool> relaunchAsAdmin() async => false;

  @override
  Future<void> openUrl(String url) async {
    try {
      await _ch.invokeMethod<bool>('open', {'url': url});
    } catch (_) {}
  }

  @override
  Future<void> revealInExplorer(String path) async {}

  // ---------------------------------------------------------------------------
  // Medya sorgusu
  // ---------------------------------------------------------------------------

  Future<List<_Media>> _query(List<String> kinds, {int minSize = 0, bool jpegOnly = false}) async {
    final raw = await _ch.invokeListMethod<dynamic>('queryMedia', {
      'kinds': kinds,
      'minSize': minSize,
      'jpegOnly': jpegOnly,
    });
    final out = <_Media>[];
    for (final e in raw ?? const []) {
      if (e is! Map) continue;
      final m = _Media.fromMap(e);
      _media[m.path] = m;
      out.add(m);
    }
    return out;
  }

  /// Adresleri gruplar hâlinde Android'e gönderir; ilerleme bildirir, iptal edilebilir.
  Future<List<T>?> _batched<T>(
    List<_Media> items,
    String method,
    Map<String, Object> extra,
    T Function(dynamic) parse, {
    required String phase,
    ProgressReporter? onProgress,
    CancelToken? token,
    int batch = 40,
    int doneBefore = 0,
    int total = 0,
  }) async {
    final out = <T>[];
    for (var i = 0; i < items.length; i += batch) {
      if (token?.isCancelled ?? false) return null;
      final part = items.sublist(i, math.min(i + batch, items.length));
      onProgress?.call(ScanProgress(
        phase: phase,
        files: doneBefore + i,
        total: total > 0 ? total : items.length,
        current: part.first.dir,
      ));
      final r = await _ch.invokeListMethod<dynamic>(method, {'uris': [for (final m in part) m.uri], ...extra});
      for (final v in r ?? List<dynamic>.filled(part.length, null)) {
        out.add(parse(v));
      }
    }
    return out;
  }

  /// Onay penceresi: "delete" (kalıcı), "trash" (çöp kutusu), "write" (değiştirme).
  Future<bool> _request(String type, List<String> uris) async {
    if (uris.isEmpty) return true;
    try {
      return await _ch.invokeMethod<bool>('request', {'type': type, 'uris': uris}) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Gereksiz dosyalar
  // ---------------------------------------------------------------------------

  @override
  Future<List<JunkCategory>?> scanJunk({ProgressReporter? onProgress, CancelToken? token}) async {
    if (!await _ensureMedia()) return null;
    onProgress?.call(ScanProgress(phase: L.t('Fotoğraf ve videolar okunuyor', 'Reading photos and videos')));
    final items = await _query(['image', 'video']);
    if (token?.isCancelled ?? false) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    bool olderThan(_Media m, int days) => m.added < now - days * 86400000;
    final rules = <(String, String, String, bool, bool Function(_Media))>[
      (
        'shots',
        L.t('Eski ekran görüntüleri', 'Old screenshots'),
        L.t('90 günden eski ekran görüntüleri', 'Screenshots older than 90 days'),
        true,
        (m) => m.dirLower.contains('screenshot') && olderThan(m, 90),
      ),
      (
        'recordings',
        L.t('Eski ekran kayıtları', 'Old screen recordings'),
        L.t('30 günden eski ekran kayıtları', 'Screen recordings older than 30 days'),
        false,
        (m) => (m.dirLower.contains('screenrecord') || m.dirLower.contains('screen record') || m.dirLower.contains('screen_record')) &&
            olderThan(m, 30),
      ),
      (
        'wa_sent',
        L.t('WhatsApp’ta gönderilenler', 'Sent on WhatsApp'),
        L.t('Gönderdiğiniz fotoğraf ve videoların WhatsApp’taki kopyaları', 'WhatsApp’s copies of photos and videos you sent'),
        false,
        (m) => m.dirLower.contains('whatsapp') && m.dirLower.contains('/sent/'),
      ),
      (
        'wa_video',
        L.t('WhatsApp videoları', 'WhatsApp videos'),
        L.t('Sohbetlerden gelen videolar', 'Videos received in chats'),
        false,
        (m) => m.dirLower.contains('whatsapp') && m.kind == 'video',
      ),
      (
        'telegram',
        L.t('Telegram medyası', 'Telegram media'),
        L.t('Telegram’dan kaydedilen fotoğraf ve videolar', 'Photos and videos saved from Telegram'),
        false,
        (m) => m.dirLower.contains('telegram'),
      ),
      (
        'downloads',
        L.t('Eski indirmeler', 'Old downloads'),
        L.t('İndirilenler’deki 90 günden eski fotoğraf ve videolar', 'Photos and videos in Downloads older than 90 days'),
        false,
        (m) => m.dirLower.startsWith('download/') && olderThan(m, 90),
      ),
    ];

    final groups = <String, List<_Media>>{};
    for (final m in items) {
      for (final r in rules) {
        if (r.$5(m)) {
          groups.putIfAbsent(r.$1, () => []).add(m);
          break; // her dosya yalnızca bir kategoride
        }
      }
    }
    _junkUris.clear();
    final result = <JunkCategory>[];
    for (final r in rules) {
      final list = groups[r.$1];
      if (list == null || list.isEmpty) continue;
      _junkUris[r.$1] = [for (final m in list) m.uri];
      result.add(JunkCategory(
        id: r.$1,
        name: r.$2,
        description: r.$3,
        sizeBytes: list.fold<int>(0, (s, m) => s + m.size),
        fileCount: list.length,
        selected: r.$4,
        warning: r.$4 ? null : L.t('Gözden geçirin', 'Review first'),
      ));
    }
    return result;
  }

  @override
  Future<CleanResult> cleanJunk(List<JunkCategory> categories, {ProgressReporter? onProgress}) async {
    final uris = [for (final c in categories) ...?_junkUris[c.id]];
    if (uris.isEmpty) return const CleanResult(freedBytes: 0, skippedFiles: 0);
    onProgress?.call(ScanProgress(phase: L.t('Onay bekleniyor', 'Waiting for confirmation')));
    final ok = await _request('delete', uris);
    if (!ok) return const CleanResult(freedBytes: 0, skippedFiles: 0);
    return CleanResult(freedBytes: categories.fold<int>(0, (s, c) => s + c.sizeBytes), skippedFiles: 0);
  }

  // ---------------------------------------------------------------------------
  // Kopya dosyalar
  // ---------------------------------------------------------------------------

  @override
  List<String> defaultUserFolders() => const ['images', 'video', 'audio'];

  @override
  Future<List<DuplicateGroup>?> findDuplicates(
    List<String> roots, {
    required int minSize,
    List<String> excluded = const [],
    ProgressReporter? onProgress,
    CancelToken? token,
  }) async {
    if (!await _ensureMedia()) return null;
    final kinds = [
      if (roots.contains('images')) 'image',
      if (roots.contains('video')) 'video',
      if (roots.contains('audio')) 'audio',
    ];
    if (kinds.isEmpty) return [];
    onProgress?.call(ScanProgress(phase: L.t('Dosyalar listeleniyor', 'Listing files')));
    final items = await _query(kinds, minSize: math.max(1, minSize));
    if (token?.isCancelled ?? false) return null;

    final bySize = <int, List<_Media>>{};
    for (final m in items) {
      bySize.putIfAbsent(m.size, () => []).add(m);
    }
    final candidates = [for (final l in bySize.values) if (l.length > 1) ...l];
    const partial = 64 * 1024;
    final compare = L.t('Karşılaştırılıyor', 'Comparing');

    // 1. aşama: ilk 64 KB
    final heads = await _batched<String?>(candidates, 'hash', {'limit': partial}, (v) => v as String?,
        phase: compare, onProgress: onProgress, token: token);
    if (heads == null) return null;
    final headGroups = <String, List<_Media>>{};
    for (var i = 0; i < candidates.length; i++) {
      final h = heads[i];
      if (h == null) continue;
      headGroups.putIfAbsent('${candidates[i].size}|$h', () => []).add(candidates[i]);
    }

    // 2. aşama: 64 KB'tan büyükler için tam içerik
    final needFull = [for (final l in headGroups.values) if (l.length > 1 && l.first.size > partial) ...l];
    final full = await _batched<String?>(needFull, 'hash', {'limit': 0}, (v) => v as String?,
        phase: compare, onProgress: onProgress, token: token);
    if (full == null) return null;
    final fullHash = <String, String>{for (var i = 0; i < needFull.length; i++) if (full[i] != null) needFull[i].uri: full[i]!};

    final finalGroups = <String, List<_Media>>{};
    for (final entry in headGroups.entries) {
      if (entry.value.length < 2) continue;
      for (final m in entry.value) {
        final key = m.size > partial ? fullHash[m.uri] : entry.key;
        if (key == null) continue;
        finalGroups.putIfAbsent('${m.size}|$key', () => []).add(m);
      }
    }

    final groups = <DuplicateGroup>[];
    for (final list in finalGroups.values) {
      if (list.length < 2) continue;
      final files = [for (final m in list) DuplicateFile(path: m.path, modified: m.when)]
        ..sort((a, b) => a.modified.compareTo(b.modified));
      groups.add(DuplicateGroup(size: list.first.size, files: files)..keepOnly(files.first));
    }
    groups.sort((a, b) => b.wastedBytes.compareTo(a.wastedBytes));
    return groups;
  }

  /// Kopyaları çöp kutusuna taşır (Android 10'da kalıcı silinir).
  @override
  Future<int> deleteFiles(List<String> paths) async {
    final uris = [for (final p in paths) ?_media[p]?.uri];
    if (uris.isEmpty) return 0;
    return await _request('trash', uris) ? uris.length : 0;
  }

  // ---------------------------------------------------------------------------
  // Disk haritası
  // ---------------------------------------------------------------------------

  @override
  String defaultUsageRoot() => storageRoot;

  @override
  Future<List<FolderUsage>?> folderUsage(String root, {ProgressReporter? onProgress, CancelToken? token}) async {
    if (!await _ensureMedia()) return null;
    onProgress?.call(ScanProgress(phase: L.t('Ölçülüyor', 'Measuring')));
    final items = await _query(['image', 'video', 'audio']);
    if (token?.isCancelled ?? false) return null;

    final base = root.replaceAll(RegExp(r'/+$'), '');
    final top = base == storageRoot || base.length <= storageRoot.length;
    final rel = top ? '' : '${base.substring(storageRoot.length + 1)}/';

    final children = <String, int>{};
    var loose = 0;
    var mediaTotal = 0;
    for (final m in items) {
      mediaTotal += m.size;
      if (!m.dir.startsWith(rel)) continue;
      final rest = m.dir.substring(rel.length);
      if (rest.isEmpty) {
        loose += m.size;
      } else {
        final seg = rest.split('/').first;
        children[seg] = (children[seg] ?? 0) + m.size;
      }
    }
    final result = [
      for (final e in children.entries) FolderUsage(name: e.key, path: '$base/${e.key}', bytes: e.value, isDir: true),
      if (loose > 0) FolderUsage(name: L.t('Bu klasördeki dosyalar', 'Files in this folder'), path: base, bytes: loose, isDir: false),
    ];
    if (top) {
      final s = await storageInfo();
      final other = s == null ? 0 : s.total - s.free - mediaTotal;
      if (other > 0) {
        result.add(FolderUsage(
          name: L.t('Uygulamalar, sistem ve diğer dosyalar', 'Apps, system and other files'),
          path: base,
          bytes: other,
          isDir: false,
        ));
      }
    }
    result.sort((a, b) => b.bytes.compareTo(a.bytes));
    return result;
  }

  // ---------------------------------------------------------------------------
  // Medya küçültücü
  // ---------------------------------------------------------------------------

  @override
  String defaultPicturesFolder() => storageRoot;

  @override
  Future<List<PhotoFile>?> findPhotos(String root, {int minSize = 1024 * 1024, ProgressReporter? onProgress, CancelToken? token}) async {
    if (!await _ensureMedia()) return null;
    onProgress?.call(ScanProgress(phase: L.t('Fotoğraflar aranıyor', 'Looking for photos')));
    final items = await _query(['image'], minSize: minSize, jpegOnly: true);
    if (token?.isCancelled ?? false) return null;
    return [for (final m in items) PhotoFile(path: m.path, sizeBytes: m.size)]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  }

  /// Fotoğraf olduğu yerde küçültülür: adı, klasörü ve galerideki yeri değişmez (Android bir kez
  /// "değiştirilsin mi" diye sorar). [CompressOptions.backup] açıksa orijinal önce
  /// "Pictures/Harrier Cleaner Yedek" albümüne kopyalanır; yedeği alınamayan fotoğrafa dokunulmaz.
  @override
  Future<CompressResult?> compressPhotos(
    List<String> paths,
    CompressOptions options, {
    ProgressReporter? onProgress,
    CancelToken? token,
  }) async {
    final selected = [for (final p in paths) ?_media[p]];
    if (selected.isEmpty) return const CompressResult(compressed: 0, skipped: 0, failed: 0, savedBytes: 0, donePaths: []);
    final prepare = L.t('Hazırlanıyor', 'Preparing');
    try {
      // 1. Kopyaları uygulamanın geçici klasörüne al
      final cacheToMedia = <String, _Media>{};
      var failed = 0;
      for (var i = 0; i < selected.length; i++) {
        if (token?.isCancelled ?? false) return null;
        final m = selected[i];
        onProgress?.call(ScanProgress(phase: prepare, files: i, total: selected.length, current: m.dir));
        final cache = await _ch.invokeMethod<String>('copyToCache', {'uri': m.uri, 'name': m.name});
        if (cache == null) {
          failed++;
        } else {
          cacheToMedia[cache] = m;
        }
      }

      // 2. Küçült (ayrı iş parçacığında, ortak kodla); orijinallere henüz dokunulmaz
      final r = await compressToTemp(cacheToMedia.keys.toList(), options.quality, options.maxDimension,
          onProgress: onProgress, token: token);
      if (r == null) return null;
      final (items, skipped, compressFailed) = r;
      failed += compressFailed;
      if (items.isEmpty) {
        return CompressResult(compressed: 0, skipped: skipped, failed: failed, savedBytes: 0, donePaths: const []);
      }

      // 3. Değiştirme onayı (tek pencere)
      onProgress?.call(ScanProgress(phase: L.t('Onay bekleniyor', 'Waiting for confirmation')));
      if (!await _request('write', [for (final it in items) cacheToMedia[it.$1]!.uri])) {
        return CompressResult(compressed: 0, skipped: skipped, failed: failed, savedBytes: 0, donePaths: const []);
      }

      // 4. Her fotoğraf için: (isteğe bağlı) yedek, sonra olduğu yerde küçültülmüş hâli yaz
      var saved = 0;
      final done = <String>[];
      for (var i = 0; i < items.length; i++) {
        final (cache, temp, oldSize, newSize, _) = items[i];
        final m = cacheToMedia[cache]!;
        onProgress?.call(ScanProgress(phase: L.t('Kaydediliyor', 'Saving'), files: i, total: items.length, bytes: saved, current: m.dir));
        String? backup;
        if (options.backup) {
          backup = await _ch.invokeMethod<String>('backupCopy', {'uri': m.uri, 'name': m.name});
          if (backup == null) {
            failed++; // yedek alınamadıysa orijinale dokunma
            continue;
          }
        }
        final ok = await _ch.invokeMethod<bool>('overwrite', {'uri': m.uri, 'src': temp}) ?? false;
        if (!ok) {
          failed++; // yazma yarıda kaldıysa yedek tek sağlam kopya olabilir: silinmez
          continue;
        }
        saved += oldSize - newSize;
        done.add(m.path);
      }
      return CompressResult(compressed: done.length, skipped: skipped, failed: failed, savedBytes: saved, donePaths: done);
    } finally {
      try {
        await _ch.invokeMethod<bool>('clearWork');
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Konum bilgisi temizleyici
  // ---------------------------------------------------------------------------

  @override
  Future<List<GpsPhoto>?> findLocationPhotos(String root, {ProgressReporter? onProgress, CancelToken? token}) async {
    if (!await _ensureMedia()) return null;
    final items = await _query(['image'], jpegOnly: true);
    final coords = await _batched<List<double>?>(
      items,
      'gps',
      const {},
      (v) => v is List && v.length == 2 ? [(v[0] as num).toDouble(), (v[1] as num).toDouble()] : null,
      phase: L.t('Fotoğraflar inceleniyor', 'Checking photos'),
      onProgress: onProgress,
      token: token,
      batch: 50,
    );
    if (coords == null) return null;
    return [
      for (var i = 0; i < items.length; i++)
        if (coords[i] != null) GpsPhoto(path: items[i].path, latitude: coords[i]![0], longitude: coords[i]![1]),
    ];
  }

  @override
  Future<(int, int)> removeLocation(List<String> paths, {ProgressReporter? onProgress}) async {
    final selected = [for (final p in paths) ?_media[p]];
    if (selected.isEmpty) return (0, 0);
    onProgress?.call(ScanProgress(phase: L.t('Onay bekleniyor', 'Waiting for confirmation')));
    if (!await _request('write', [for (final m in selected) m.uri])) return (0, 0);
    var cleaned = 0;
    var failed = 0;
    for (var i = 0; i < selected.length; i++) {
      final m = selected[i];
      onProgress?.call(ScanProgress(phase: L.t('Konum siliniyor', 'Removing location'), files: i, total: selected.length, current: m.dir));
      try {
        final bytes = await _ch.invokeMethod<Uint8List>('readBytes', {'uri': m.uri, 'original': true});
        if (bytes == null) {
          failed++;
          continue;
        }
        final stripped = await _stripInIsolate(bytes);
        if (stripped == null) continue; // konum yokmuş
        if (!isJpeg(stripped)) {
          failed++;
          continue;
        }
        final ok = await _ch.invokeMethod<bool>('writeBytes', {'uri': m.uri, 'bytes': stripped}) ?? false;
        ok ? cleaned++ : failed++;
      } catch (_) {
        failed++;
      }
    }
    return (cleaned, failed);
  }

  // ---------------------------------------------------------------------------
  // Pil, cihaz, canlı ölçüm
  // ---------------------------------------------------------------------------

  @override
  Future<BatteryInfo?> batteryInfo() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('battery');
      if (m == null) return null;
      return BatteryInfo(
        name: '',
        designCapacity: 0,
        fullChargeCapacity: 0,
        cycleCount: (m['cycles'] as num?)?.toInt(),
        chemistry: m['technology'] as String? ?? '',
        level: (m['level'] as num?)?.toInt(),
        temperature: (m['temperature'] as num?)?.toDouble(),
        voltageMv: (m['voltage'] as num?)?.toInt(),
        charging: m['charging'] as bool?,
        status: m['health'] as String?,
        estimatedFullMah: (m['estimatedFull'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<DiskHealth>> diskHealth() async => const [];

  @override
  Future<void> openBatteryReport() async {}

  @override
  Future<SystemInfo?> systemInfo() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('system');
      if (m == null) return null;
      final cores = (m['cores'] as num?)?.toInt() ?? 0;
      final boot = (m['boot'] as num?)?.toInt();
      return SystemInfo(
        cpuName: m['cpu'] as String? ?? '',
        cores: cores,
        threads: cores,
        maxMhz: (m['maxMhz'] as num?)?.toInt() ?? 0,
        totalRam: (m['ram'] as num?)?.toInt() ?? 0,
        osName: m['os'] as String? ?? 'Android',
        osBuild: 'API ${m['sdk'] ?? ''}',
        gpus: const [],
        bootTime: boot == null ? null : DateTime.fromMillisecondsSinceEpoch(boot),
        manufacturer: m['maker'] as String? ?? '',
        model: m['model'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<LiveStats> liveStats() {
    Timer? timer;
    int? lastRx;
    int? lastTx;
    DateTime? lastAt;
    late final StreamController<LiveStats> controller;

    Future<void> sample() async {
      try {
        final m = await _ch.invokeMapMethod<String, dynamic>('live');
        if (m == null || controller.isClosed) return;
        final now = DateTime.now();
        final rx = (m['rx'] as num?)?.toInt() ?? -1;
        final tx = (m['tx'] as num?)?.toInt() ?? -1;
        var down = 0;
        var up = 0;
        final prevAt = lastAt;
        if (prevAt != null && lastRx != null && lastTx != null && rx >= 0 && tx >= 0) {
          final secs = math.max(0.001, now.difference(prevAt).inMilliseconds / 1000);
          down = math.max(0, ((rx - lastRx!) / secs).round());
          up = math.max(0, ((tx - lastTx!) / secs).round());
        }
        lastRx = rx;
        lastTx = tx;
        lastAt = now;
        controller.add(LiveStats(
          cpuMhz: (m['mhz'] as num?)?.toInt() ?? 0,
          ramAvailable: (m['avail'] as num?)?.toInt() ?? 0,
          netDown: down,
          netUp: up,
          temperature: (m['temp'] as num?)?.toDouble(),
        ));
      } catch (_) {}
    }

    controller = StreamController<LiveStats>(
      onListen: () {
        sample();
        timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => sample());
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // Uygulamalar ve izinler
  // ---------------------------------------------------------------------------

  @override
  Future<List<InstalledApp>> installedApps() async {
    try {
      final raw = await _ch.invokeListMethod<dynamic>('apps');
      final apps = <InstalledApp>[
        for (final e in raw ?? const [])
          if (e is Map)
            InstalledApp(
              name: e['name'] as String? ?? '',
              uninstallCommand: e['pkg'] as String? ?? '',
              registryKey: e['pkg'] as String? ?? '',
              version: e['version'] as String? ?? '',
              installDate: (e['installed'] as num?) == null ? null : DateTime.fromMillisecondsSinceEpoch((e['installed'] as num).toInt()),
              sizeBytes: (e['size'] as num?)?.toInt() ?? 0,
            ),
      ];
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return apps;
    } catch (_) {
      return [];
    }
  }

  /// Android'in kaldırma onay penceresini açar ve kapanmasını bekler.
  @override
  Future<String?> runUninstaller(InstalledApp app) async {
    try {
      await _ch.invokeMethod<bool>('uninstall', {'pkg': app.registryKey});
      return null;
    } catch (_) {
      return L.t('Kaldırma penceresi açılamadı.', 'The uninstall dialog couldn’t be opened.');
    }
  }

  @override
  bool isSafeLeftover(String path) => false;

  @override
  Future<bool> recycleFolder(String path) async => false;

  @override
  Future<PermissionOverview?> permissions() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('permissions');
      if (m == null) return null;
      final uses = <PermissionUse>[];
      for (final e in (m['uses'] as List?) ?? const []) {
        if (e is! Map) continue;
        final kind = switch (e['kind']) {
          'camera' => PermissionKind.camera,
          'microphone' => PermissionKind.microphone,
          _ => PermissionKind.location,
        };
        final background = e['background'] == true;
        uses.add(PermissionUse(
          kind: kind,
          appName: background ? '${e['app']} · ${L.t('arka planda da', 'also in background')}' : '${e['app']}',
          detail: e['pkg'] as String? ?? '',
          storeApp: true,
          allowed: true,
        ));
      }
      uses.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
      return PermissionOverview(
        enabled: {
          PermissionKind.camera: null,
          PermissionKind.microphone: null,
          PermissionKind.location: m['location'] as bool?,
        },
        uses: uses,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openPrivacySettings(PermissionKind kind) => openUrl('settings:privacy');

  // ---------------------------------------------------------------------------
  // Windows'a özgü (Android'de yok)
  // ---------------------------------------------------------------------------

  @override
  Future<List<StartupItem>> startupItems() async => [];

  @override
  Future<String?> setStartupEnabled(StartupItem item, bool enabled) async => null;
}

/// Ayrı iş parçacığında konum silme. Bilerek üst düzey ve async olmayan bir fonksiyon:
/// başka isolate'a gönderilen closure yalnızca [bytes]'ı yakalar.
Future<Uint8List?> _stripInIsolate(Uint8List bytes) => Isolate.run(() => stripGps(bytes));

/// MediaStore'daki bir dosya.
class _Media {
  _Media({
    required this.uri,
    required this.name,
    required this.dir,
    required this.size,
    required this.modified,
    required this.added,
    required this.taken,
    required this.kind,
  });

  factory _Media.fromMap(Map<dynamic, dynamic> e) => _Media(
        uri: e['uri'] as String,
        name: e['name'] as String? ?? '',
        dir: e['dir'] as String? ?? '',
        size: (e['size'] as num?)?.toInt() ?? 0,
        modified: (e['modified'] as num?)?.toInt() ?? 0,
        added: (e['added'] as num?)?.toInt() ?? 0,
        taken: (e['taken'] as num?)?.toInt() ?? 0,
        kind: e['kind'] as String? ?? 'image',
      );

  final String uri;
  final String name;

  /// Göreli klasör, "/" ile biter: "DCIM/Camera/".
  final String dir;
  final int size;
  final int modified;
  final int added;
  final int taken;
  final String kind;

  String get path => '$dir$name';
  String get dirLower => dir.toLowerCase();

  /// Fotoğrafın çekildiği (yoksa değiştirildiği) zaman.
  DateTime get when => DateTime.fromMillisecondsSinceEpoch(taken > 0 ? taken : (modified > 0 ? modified : added));
}
