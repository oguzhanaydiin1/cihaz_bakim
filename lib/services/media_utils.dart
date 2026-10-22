import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/models.dart';
import 'exif_gps.dart';
import 'fs_utils.dart';
import 'isolate_runner.dart';

// Fotoğraf işlemleri. *Sync fonksiyonlar ayrı bir isolate'ta çalışır.
// Sarmalayıcılar bilerek async olmayan üst düzey fonksiyonlardır (bkz. fs_utils.dart).

bool _isJpegPath(String p) {
  final l = p.toLowerCase();
  return l.endsWith('.jpg') || l.endsWith('.jpeg');
}

/// Dosyanın içeriğini güvenle değiştirir: önce yedek adına taşı, yenisini koy, yedeği sil.
/// Bir adım başarısız olursa orijinal geri konur. Değiştirilme tarihi korunur.
bool replaceFileSafely(String path, String tmpPath, DateTime modified) {
  final bak = '$path.hc_bak';
  try {
    File(path).renameSync(bak);
  } catch (_) {
    _tryDelete(tmpPath);
    return false;
  }
  try {
    File(tmpPath).renameSync(path);
  } catch (_) {
    try {
      File(bak).renameSync(path);
    } catch (_) {}
    _tryDelete(tmpPath);
    return false;
  }
  _tryDelete(bak);
  try {
    File(path).setLastModifiedSync(modified);
  } catch (_) {}
  return true;
}

void _tryDelete(String p) {
  try {
    File(p).deleteSync();
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Büyük fotoğrafları bulma
// ---------------------------------------------------------------------------

Future<List<PhotoFile>?> findLargePhotos(String root, int minSize, {ProgressReporter? onProgress, CancelToken? token}) =>
    runCancellable((r) => findLargePhotosSync(root, minSize, r), onProgress: onProgress, token: token);

List<PhotoFile> findLargePhotosSync(String root, int minSize, ProgressReporter report) {
  final result = <PhotoFile>[];
  var seen = 0;
  final dir = Directory(root);
  if (!dir.existsSync()) return result;
  for (final f in walkFiles(dir, skipNoise: true)) {
    if (!_isJpegPath(f.path)) continue;
    seen++;
    try {
      final size = f.lengthSync();
      if (size >= minSize) result.add(PhotoFile(path: f.path, sizeBytes: size));
    } catch (_) {}
    report(ScanProgress(phase: 'Fotoğraflar aranıyor', files: seen, current: f.parent.path));
  }
  result.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  return result;
}

// ---------------------------------------------------------------------------
// Sıkıştırma
// ---------------------------------------------------------------------------

/// Sıkıştırılmış hali geçici dosyaya yazılan bir fotoğraf.
typedef CompressedTemp = (String original, String temp, int oldSize, int newSize, int modifiedMs);

/// Fotoğrafları sıkıştırıp yanlarına geçici dosya olarak yazar; orijinallere dokunmaz.
/// (başarılılar, atlanan, başarısız) döndürür.
Future<(List<CompressedTemp>, int, int)?> compressToTemp(
  List<String> paths,
  int quality,
  int maxDimension, {
  ProgressReporter? onProgress,
  CancelToken? token,
}) =>
    runCancellable((r) => compressToTempSync(paths, quality, maxDimension, r), onProgress: onProgress, token: token);

(List<CompressedTemp>, int, int) compressToTempSync(
  List<String> paths,
  int quality,
  int maxDimension,
  ProgressReporter report,
) {
  final done = <CompressedTemp>[];
  var skipped = 0;
  var failed = 0;
  var saved = 0;
  for (var i = 0; i < paths.length; i++) {
    final path = paths[i];
    report(ScanProgress(phase: 'Küçültülüyor', files: i, total: paths.length, bytes: saved, current: path));
    try {
      final file = File(path);
      final bytes = file.readAsBytesSync();
      final modified = file.lastModifiedSync();
      var image = img.decodeJpg(bytes);
      if (image == null) {
        failed++;
        continue;
      }
      image = img.bakeOrientation(image); // yön bilgisini görüntüye uygula
      final longest = math.max(image.width, image.height);
      if (maxDimension > 0 && longest > maxDimension) {
        image = image.width >= image.height
            ? img.copyResize(image, width: maxDimension, interpolation: img.Interpolation.average)
            : img.copyResize(image, height: maxDimension, interpolation: img.Interpolation.average);
      }
      final out = img.encodeJpg(image, quality: quality, chroma: img.JpegChroma.yuv420);
      // %10'dan az kazanç varsa dokunma: kaliteyi boşuna düşürmeyelim.
      if (out.length >= bytes.length * 0.9) {
        skipped++;
        continue;
      }
      final tmp = '$path.hc_tmp';
      File(tmp).writeAsBytesSync(out, flush: true);
      done.add((path, tmp, bytes.length, out.length, modified.millisecondsSinceEpoch));
      saved += bytes.length - out.length;
    } catch (_) {
      failed++;
    }
  }
  report(ScanProgress(phase: 'Küçültülüyor', files: paths.length, total: paths.length, bytes: saved));
  return (done, skipped, failed);
}

/// İptal veya hata sonrası kalan geçici dosyaları temizler.
void cleanupTemps(List<String> paths) {
  for (final p in paths) {
    _tryDelete('$p.hc_tmp');
  }
}

// ---------------------------------------------------------------------------
// Konum bilgisi
// ---------------------------------------------------------------------------

Future<List<GpsPhoto>?> findGpsPhotos(String root, {ProgressReporter? onProgress, CancelToken? token}) =>
    runCancellable((r) => findGpsPhotosSync(root, r), onProgress: onProgress, token: token);

List<GpsPhoto> findGpsPhotosSync(String root, ProgressReporter report) {
  final result = <GpsPhoto>[];
  var seen = 0;
  final dir = Directory(root);
  if (!dir.existsSync()) return result;
  for (final f in walkFiles(dir, skipNoise: true)) {
    if (!_isJpegPath(f.path)) continue;
    seen++;
    report(ScanProgress(phase: 'Fotoğraflar inceleniyor', files: seen, current: f.parent.path));
    try {
      // EXIF dosyanın başında olur; tamamını okumaya gerek yok.
      final raf = f.openSync();
      final head = raf.readSync(256 * 1024);
      raf.closeSync();
      final gps = readGps(head);
      if (gps != null) {
        result.add(GpsPhoto(path: f.path, latitude: gps.latitude, longitude: gps.longitude));
      }
    } catch (_) {}
  }
  return result;
}

/// Seçili fotoğraflardan konum bilgisini siler. (temizlenen, başarısız) döndürür.
Future<(int, int)?> stripGpsFrom(List<String> paths, {ProgressReporter? onProgress}) =>
    runCancellable((r) => stripGpsSync(paths, r), onProgress: onProgress);

(int, int) stripGpsSync(List<String> paths, ProgressReporter report) {
  var cleaned = 0;
  var failed = 0;
  for (var i = 0; i < paths.length; i++) {
    final path = paths[i];
    report(ScanProgress(phase: 'Konum siliniyor', files: i, total: paths.length, current: path));
    try {
      final file = File(path);
      final modified = file.lastModifiedSync();
      final stripped = stripGps(file.readAsBytesSync());
      if (stripped == null) continue; // konum yokmuş
      if (!isJpeg(stripped)) {
        failed++;
        continue;
      }
      final tmp = '$path.hc_tmp';
      File(tmp).writeAsBytesSync(stripped, flush: true);
      if (replaceFileSafely(path, tmp, modified)) {
        cleaned++;
      } else {
        failed++;
      }
    } catch (_) {
      failed++;
    }
  }
  return (cleaned, failed);
}
