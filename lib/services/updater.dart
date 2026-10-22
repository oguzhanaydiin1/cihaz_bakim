import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/app_info.dart';
import '../core/i18n.dart';

/// Sunucudaki yeni sürüm bilgisi.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.url,
    required this.sha256,
    required this.size,
  });

  final String version;
  final String notes;

  /// Kurulum dosyasının adresi.
  final String url;
  final String sha256;
  final int size;
}

enum UpdateStatus { checking, latest, available, downloading, ready, error, unsupported }

/// Uygulama içi güncelleme.
///
/// oalabs.dev/harrier/latest.json dosyasına bakar:
/// {"version": "0.2.0", "notes": {"tr": "...", "en": "..."},
///  "windows": {"url": "https://.../HarrierCleaner-Setup-0.2.0.exe", "sha256": "...", "size": 123}}
/// Yeni sürüm varsa kurulum dosyasını indirir, SHA-256 ile doğrular ve sessiz kurulumu başlatır.
/// Kurulum, açık uygulamayı kapatır ve bitince yeniden açar.
class Updater {
  /// Güncelleme yalnızca kurulmuş (release) Windows sürümünde çalışır.
  static bool get supported => Platform.isWindows && kReleaseMode;

  /// "1.10.0" > "1.9.2"
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v.replaceFirst(RegExp(r'^v', caseSensitive: false), '').split(RegExp(r'[.+-]')).map((x) => int.tryParse(x) ?? 0).toList();
    final pa = parts(a);
    final pb = parts(b);
    for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
      final d = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
      if (d != 0) return d > 0 ? 1 : -1;
    }
    return 0;
  }

  static HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'HarrierCleaner/${AppInfo.version}';

  /// Yeni sürüm varsa bilgisini, yoksa null döndürür. Bağlantı hatasında istisna fırlatır.
  static Future<UpdateInfo?> check() async {
    final client = _client();
    try {
      final req = await client.getUrl(Uri.parse('${AppInfo.updateManifest}?t=${DateTime.now().millisecondsSinceEpoch}'));
      req.headers.set('Cache-Control', 'no-cache');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final data = jsonDecode(await res.transform(utf8.decoder).join());
      if (data is! Map<String, dynamic>) return null;
      final version = '${data['version'] ?? ''}';
      if (version.isEmpty || compareVersions(version, AppInfo.version) <= 0) return null;
      final win = data['windows'];
      if (win is! Map<String, dynamic>) return null;
      final url = '${win['url'] ?? ''}';
      if (!url.startsWith('https://')) return null;
      final notes = data['notes'];
      return UpdateInfo(
        version: version,
        notes: notes is Map ? '${notes[L.code] ?? notes['tr'] ?? ''}' : '${notes ?? ''}',
        url: url,
        sha256: '${win['sha256'] ?? ''}'.toLowerCase(),
        size: (win['size'] as num?)?.toInt() ?? 0,
      );
    } finally {
      client.close();
    }
  }

  /// Kurulum dosyasını indirir ve doğrular; dosyanın yolunu döndürür.
  static Future<String> download(UpdateInfo info, {void Function(double progress)? onProgress}) async {
    final target = File('${Directory.systemTemp.path}${Platform.pathSeparator}HarrierCleaner-Setup-${info.version}.exe');
    final client = _client();
    try {
      final req = await client.getUrl(Uri.parse(info.url));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength > 0 ? res.contentLength : info.size;
      final sink = target.openWrite();
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    final digest = await sha256.bind(target.openRead()).first;
    if (info.sha256.isEmpty || digest.toString() != info.sha256) {
      try {
        await target.delete();
      } catch (_) {}
      throw StateError(L.t('İndirilen dosya doğrulanamadı.', 'The downloaded file could not be verified.'));
    }
    return target.path;
  }

  /// Sessiz kurulumu başlatır ve uygulamayı kapatır. Kurulum bitince uygulama yeniden açılır.
  static Future<void> install(String installerPath) async {
    await Process.start(
      installerPath,
      ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
