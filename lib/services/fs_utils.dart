import 'dart:io';

import 'package:crypto/crypto.dart';

import '../core/format.dart';
import '../models/models.dart';
import 'isolate_runner.dart';

// Bu dosyadaki *Sync fonksiyonlar runCancellable ile ayrı bir isolate'ta çalıştırılır;
// böylece tarama sırasında arayüz donmaz ve işlem iptal edilebilir.
//
// Aşağıdaki sarmalayıcılar bilerek async OLMAYAN üst düzey fonksiyonlardır: başka
// isolate'a gönderilen closure yalnızca kendi parametrelerini yakalar. Closure'u bir
// async metodun içinde oluşturmak, metodun iç durumunu da yakalayıp "unsendable" hatası verir.

Future<List<(int, int)>?> measureAll(List<PathJob> jobs, {ProgressReporter? onProgress, CancelToken? token}) =>
    runCancellable((r) => measureAllSync(jobs, r), onProgress: onProgress, token: token);

Future<(int, int)?> cleanAll(List<PathJob> jobs, {ProgressReporter? onProgress}) =>
    runCancellable((r) => cleanAllSync(jobs, r), onProgress: onProgress);

Future<List<DuplicateGroup>?> findDuplicatesIn(
  List<String> roots, {
  required int minSize,
  required List<String> excluded,
  ProgressReporter? onProgress,
  CancelToken? token,
}) =>
    runCancellable((r) => findDuplicatesSync(roots, minSize, excluded, r), onProgress: onProgress, token: token);

Future<List<FolderUsage>?> folderUsageOf(String root, {ProgressReporter? onProgress, CancelToken? token}) =>
    runCancellable((r) => folderUsageSync(root, r), onProgress: onProgress, token: token);

/// Temizlik yalnızca mutlak ve sürücü kökünden daha derin yollarda yapılır.
/// Boş bir ortam değişkeni yüzünden yanlış klasörün silinmesini önler.
bool isSafeRoot(String path) {
  final p = path.trim();
  if (p.isEmpty || !Directory(p).isAbsolute) return false;
  final depth = p.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).length;
  return depth >= 2; // "C:\" veya "/" gibi kökler reddedilir
}

/// Hariç tutulan klasör listesini karşılaştırmaya hazır hale getirir.
List<String> normalizeExcluded(List<String> excluded) => excluded
    .map((e) => e.trim().replaceAll(RegExp(r'[\\/]+$'), '').toLowerCase())
    .where((e) => e.isNotEmpty)
    .toList();

bool _isExcluded(String path, List<String> excluded) {
  if (excluded.isEmpty) return false;
  final p = path.toLowerCase();
  for (final x in excluded) {
    if (p == x || p.startsWith('$x\\') || p.startsWith('$x/')) return true;
  }
  return false;
}

/// Klasör ağacındaki dosyaları gezer. Erişilemeyen klasörleri sessizce atlar,
/// sembolik bağlantıları ve junction'ları izlemez (sonsuz döngüyü önler).
Iterable<File> walkFiles(
  Directory root, {
  bool skipNoise = false,
  List<Directory>? dirsOut,
  List<String> excluded = const [],
}) sync* {
  final stack = <Directory>[root];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in entries) {
      if (e is File) {
        yield e;
      } else if (e is Directory) {
        if (skipNoise) {
          final name = baseName(e.path);
          if (name.startsWith('.') || name == 'node_modules' || name == r'$RECYCLE.BIN') continue;
        }
        if (_isExcluded(e.path, excluded)) continue;
        dirsOut?.add(e);
        stack.add(e);
      }
    }
  }
}

bool _matches(File f, String? prefix) =>
    prefix == null || baseName(f.path).toLowerCase().startsWith(prefix.toLowerCase());

// ---------------------------------------------------------------------------
// Gereksiz dosyalar: ölçme ve temizleme
// ---------------------------------------------------------------------------

/// Bir temizlik işi: klasörler ve isteğe bağlı dosya adı öneki.
typedef PathJob = (List<String>, String?);

/// Her iş için (bayt, dosya sayısı) döndürür.
List<(int, int)> measureAllSync(List<PathJob> jobs, ProgressReporter report) {
  var totalFiles = 0;
  var totalBytes = 0;
  final results = <(int, int)>[];
  for (final (paths, prefix) in jobs) {
    var bytes = 0;
    var count = 0;
    for (final p in paths) {
      final dir = Directory(p);
      if (!dir.existsSync()) continue;
      for (final f in walkFiles(dir)) {
        if (!_matches(f, prefix)) continue;
        try {
          final len = f.lengthSync();
          bytes += len;
          count++;
          totalBytes += len;
          totalFiles++;
          report(ScanProgress(phase: 'Ölçülüyor', files: totalFiles, bytes: totalBytes, current: f.parent.path));
        } catch (_) {}
      }
    }
    results.add((bytes, count));
  }
  return results;
}

/// Klasörlerin İÇİNDEKİ dosyaları siler; klasörlerin kendisine dokunmaz.
/// Kullanımda olan dosyalar atlanır. (silinen bayt, atlanan dosya) döndürür.
(int, int) cleanAllSync(List<PathJob> jobs, ProgressReporter report) {
  var freed = 0;
  var skipped = 0;
  var deleted = 0;
  for (final (paths, prefix) in jobs) {
    for (final p in paths) {
      if (!isSafeRoot(p)) continue;
      final root = Directory(p);
      if (!root.existsSync()) continue;
      final dirs = <Directory>[];
      final files = walkFiles(root, dirsOut: dirs).toList();
      for (final f in files) {
        if (!_matches(f, prefix)) continue;
        int size;
        try {
          size = f.lengthSync();
        } catch (_) {
          size = 0;
        }
        try {
          f.deleteSync();
          freed += size;
          deleted++;
          report(ScanProgress(phase: 'Siliniyor', files: deleted, bytes: freed, current: f.parent.path));
        } catch (_) {
          skipped++; // kullanımda veya izin yok
        }
      }
      // Boşalan alt klasörleri derinden yüzeye doğru kaldır (kök klasör kalır).
      if (prefix == null) {
        dirs.sort((a, b) => b.path.length.compareTo(a.path.length));
        for (final d in dirs) {
          try {
            d.deleteSync(); // recursive değil: yalnızca boşsa silinir
          } catch (_) {}
        }
      }
    }
  }
  return (freed, skipped);
}

// ---------------------------------------------------------------------------
// Kopya dosya bulma
// ---------------------------------------------------------------------------

/// Önce boyuta, sonra ilk 64 KB'ın özetine, en son tam içerik özetine göre gruplar.
/// Böylece yalnızca gerçekten aday olan dosyalar baştan sona okunur.
List<DuplicateGroup> findDuplicatesSync(
  List<String> roots,
  int minSize,
  List<String> excluded,
  ProgressReporter report,
) {
  const partialSize = 64 * 1024;
  final ex = normalizeExcluded(excluded);
  final bySize = <int, List<String>>{};
  final seen = <String>{};
  var listed = 0;
  var listedBytes = 0;

  // 1. aşama: dosyaları listele
  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync() || _isExcluded(root, ex)) continue;
    for (final f in walkFiles(dir, skipNoise: true, excluded: ex)) {
      final key = Platform.isWindows ? f.path.toLowerCase() : f.path;
      if (!seen.add(key)) continue; // iç içe seçilmiş klasörler
      int size;
      try {
        size = f.lengthSync();
      } catch (_) {
        continue;
      }
      listed++;
      listedBytes += size;
      report(ScanProgress(phase: 'Dosyalar listeleniyor', files: listed, bytes: listedBytes, current: f.parent.path));
      if (size < minSize) continue;
      bySize.putIfAbsent(size, () => []).add(f.path);
    }
  }

  // 2. aşama: aynı boyuttaki dosyaların içeriğini karşılaştır
  final candidates = bySize.entries.where((e) => e.value.length > 1).toList();
  final candidateCount = candidates.fold<int>(0, (s, e) => s + e.value.length);
  var compared = 0;
  final groups = <DuplicateGroup>[];

  for (final entry in candidates) {
    String? hashAndReport(String p, {int? limit}) {
      final h = _hash(p, limit: limit);
      if (limit != null) compared++;
      report(ScanProgress(phase: 'Karşılaştırılıyor', files: compared, total: candidateCount, current: p));
      return h;
    }

    for (final partial in _groupBy(entry.value, (p) => hashAndReport(p, limit: partialSize))) {
      if (partial.length < 2) continue;
      final same = entry.key <= partialSize ? [partial] : _groupBy(partial, (p) => hashAndReport(p));
      for (final paths in same) {
        if (paths.length < 2) continue;
        final files = <DuplicateFile>[];
        for (final p in paths) {
          try {
            files.add(DuplicateFile(path: p, modified: File(p).lastModifiedSync()));
          } catch (_) {}
        }
        if (files.length < 2) continue;
        files.sort((a, b) => a.modified.compareTo(b.modified));
        final group = DuplicateGroup(size: entry.key, files: files);
        group.keepOnly(files.first); // varsayılan: en eski dosya korunur
        groups.add(group);
      }
    }
  }
  groups.sort((a, b) => b.wastedBytes.compareTo(a.wastedBytes));
  return groups;
}

List<List<String>> _groupBy(List<String> paths, String? Function(String) keyOf) {
  final map = <String, List<String>>{};
  for (final p in paths) {
    final k = keyOf(p);
    if (k == null) continue; // okunamayan dosya
    map.putIfAbsent(k, () => []).add(p);
  }
  return map.values.toList();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Dosyanın SHA-1 özeti. [limit] verilirse yalnızca ilk [limit] bayt okunur.
String? _hash(String path, {int? limit}) {
  const chunk = 1 << 20;
  RandomAccessFile? raf;
  try {
    raf = File(path).openSync();
    final sink = _DigestSink();
    final input = sha1.startChunkedConversion(sink);
    var remaining = limit ?? -1;
    while (remaining != 0) {
      final n = (remaining < 0 || remaining > chunk) ? chunk : remaining;
      final data = raf.readSync(n);
      if (data.isEmpty) break;
      input.add(data);
      if (remaining > 0) remaining -= data.length;
    }
    input.close();
    return sink.value?.toString();
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Klasör boyutları (disk haritası)
// ---------------------------------------------------------------------------

List<FolderUsage> folderUsageSync(String root, ProgressReporter report) {
  final result = <FolderUsage>[];
  var looseBytes = 0;
  var files = 0;
  var bytesSoFar = 0;
  List<FileSystemEntity> entries;
  try {
    entries = Directory(root).listSync(followLinks: false);
  } catch (_) {
    return result;
  }
  for (final e in entries) {
    if (e is Directory) {
      var bytes = 0;
      for (final f in walkFiles(e)) {
        try {
          final len = f.lengthSync();
          bytes += len;
          bytesSoFar += len;
          files++;
          report(ScanProgress(phase: 'Ölçülüyor', files: files, bytes: bytesSoFar, current: f.parent.path));
        } catch (_) {}
      }
      result.add(FolderUsage(name: baseName(e.path), path: e.path, bytes: bytes, isDir: true));
    } else if (e is File) {
      try {
        looseBytes += e.lengthSync();
      } catch (_) {}
    }
  }
  if (looseBytes > 0) {
    result.add(FolderUsage(name: 'Bu klasördeki dosyalar', path: root, bytes: looseBytes, isDir: false));
  }
  result.removeWhere((u) => u.bytes == 0);
  result.sort((a, b) => b.bytes.compareTo(a.bytes));
  return result;
}
