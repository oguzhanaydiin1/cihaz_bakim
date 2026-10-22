import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_info.dart';
import '../core/i18n.dart';

/// Yakalanan bir hata.
class ErrorEntry {
  const ErrorEntry({required this.time, required this.message, required this.stack});
  final DateTime time;
  final String message;
  final String stack;

  String format() => '[${time.toIso8601String()}] $message\n$stack';
}

/// Uygulamadaki beklenmeyen hataları yakalar.
///
/// - Her hata bilgisayardaki günlük dosyasına yazılır (%APPDATA%\HarrierCleaner\errors.log).
/// - Kullanıcı izin verdiyse (Ayarlar'dan kapatılabilir) isimsiz bir rapor api.oalabs.dev'e gönderilir.
///   Rapordan kullanıcı adı ve klasör yolları temizlenir; dosya adları, içerikler gönderilmez.
class ErrorReporter {
  static String? _logPath;
  static bool Function() _canSend = () => false;
  static String Function() _installId = () => '';
  static final recent = <ErrorEntry>[];
  static final _sentKeys = <String>{};
  static int _sentThisSession = 0;

  static void init({String? logPath, required bool Function() canSend, required String Function() installId}) {
    _logPath = logPath;
    _canSend = canSend;
    _installId = installId;

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      record(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      return true; // uygulama çökmesin
    };
  }

  /// Ekranda gösterilmek ve sorun bildirimine eklenmek için günlüğün son kısmı.
  static String recentLog({int maxChars = 6000}) {
    try {
      final p = _logPath;
      if (p != null && File(p).existsSync()) {
        final text = File(p).readAsStringSync();
        return text.length > maxChars ? text.substring(text.length - maxChars) : text;
      }
    } catch (_) {}
    return recent.map((e) => e.format()).join('\n\n');
  }

  static String _scrub(String text) {
    var t = text;
    final env = Platform.environment;
    for (final key in ['USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'TEMP']) {
      final v = env[key];
      if (v != null && v.length > 3) t = t.replaceAll(v, '%$key%');
    }
    final user = env['USERNAME'];
    if (user != null && user.length > 2) t = t.replaceAll(user, '<kullanıcı>');
    return t;
  }

  static void record(Object error, StackTrace? stack) {
    final entry = ErrorEntry(
      time: DateTime.now(),
      message: _scrub(error.toString()).trim(),
      stack: _scrub((stack ?? StackTrace.empty).toString()).split('\n').take(25).join('\n'),
    );
    recent.add(entry);
    if (recent.length > 20) recent.removeAt(0);
    _writeLog(entry);
    _send(entry);
  }

  static void _writeLog(ErrorEntry e) {
    final p = _logPath;
    if (p == null) return;
    try {
      final file = File(p);
      file.parent.createSync(recursive: true);
      // Dosya 256 KB'ı geçerse eski yarısını at.
      if (file.existsSync() && file.lengthSync() > 256 * 1024) {
        final text = file.readAsStringSync();
        file.writeAsStringSync(text.substring(text.length ~/ 2));
      }
      file.writeAsStringSync('${e.format()}\n\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  static Future<void> _send(ErrorEntry e) async {
    // Geliştirme sırasında rapor gönderilmez; aynı hata bir oturumda bir kez, en fazla 10 rapor.
    if (!kReleaseMode || !_canSend() || _sentThisSession >= 10) return;
    final key = '${e.message}|${e.stack.split('\n').first}';
    if (!_sentKeys.add(key)) return;
    _sentThisSession++;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse(AppInfo.reportEndpoint));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'app': AppInfo.appId,
        'v': AppInfo.version,
        'id': _installId(),
        'os': Platform.operatingSystemVersion,
        'lang': L.code,
        'msg': e.message.length > 500 ? e.message.substring(0, 500) : e.message,
        'stack': e.stack.length > 4000 ? e.stack.substring(0, 4000) : e.stack,
      }));
      await req.close().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Rapor gönderilemezse sessizce vazgeç.
    } finally {
      client.close();
    }
  }
}
