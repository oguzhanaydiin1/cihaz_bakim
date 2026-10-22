import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

/// Ayarları ve geçmişi bir JSON dosyasında saklar.
/// [path] null ise (ör. Android örnek modu) yalnızca bellekte tutulur.
class SettingsStore {
  SettingsStore(this.path, {this.legacyPath});

  final String? path;

  /// Eski sürümün ayar dosyası (ör. isim değişmeden önceki klasör).
  final String? legacyPath;

  Future<AppSettings> load() async {
    final p = path;
    if (p == null) return AppSettings();
    try {
      var file = File(p);
      final legacy = legacyPath;
      if (!await file.exists() && legacy != null && await File(legacy).exists()) {
        file = File(legacy); // geçmiş kaybolmasın: eski dosyadan oku, ilk kayıtta yeni yere yazılır
      }
      if (!await file.exists()) return AppSettings();
      final data = jsonDecode(await file.readAsString());
      if (data is Map<String, dynamic>) return AppSettings.fromJson(data);
    } catch (_) {
      // Bozuk dosya: varsayılanlarla devam et.
    }
    return AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    final p = path;
    if (p == null) return;
    try {
      final file = File(p);
      await file.parent.create(recursive: true);
      // Önce geçici dosyaya yaz, sonra yerine koy: yazarken kapanırsa dosya bozulmaz.
      final tmp = File('$p.tmp');
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(settings.toJson()), flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(p);
    } catch (_) {}
  }
}
