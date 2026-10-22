import '../core/format.dart';

// ---------------------------------------------------------------------------
// İlerleme
// ---------------------------------------------------------------------------

/// Süren bir taramanın anlık durumu.
class ScanProgress {
  const ScanProgress({this.phase = '', this.files = 0, this.total = 0, this.bytes = 0, this.current = ''});

  /// Hangi aşamada olunduğu (ör. "Karşılaştırılıyor").
  final String phase;

  /// İşlenen dosya sayısı.
  final int files;

  /// Toplam dosya sayısı biliniyorsa (0 = bilinmiyor).
  final int total;
  final int bytes;

  /// Şu an taranan klasör.
  final String current;
}

// ---------------------------------------------------------------------------
// Gereksiz dosyalar
// ---------------------------------------------------------------------------

enum JunkKind { directories, recycleBin }

/// Gereksiz dosya kategorisi (ör. geçici dosyalar, tarayıcı önbelleği).
class JunkCategory {
  JunkCategory({
    required this.id,
    required this.name,
    required this.description,
    this.paths = const [],
    this.kind = JunkKind.directories,
    this.filePrefix,
    this.processName,
    this.requiresAdmin = false,
    this.sizeBytes = 0,
    this.fileCount = 0,
    this.warning,
    this.selected = true,
    this.blocked = false,
  });

  final String id;
  final String name;
  final String description;

  /// Taranacak klasörler.
  final List<String> paths;
  final JunkKind kind;

  /// Yalnızca bu önekle başlayan dosyalar sayılır (ör. "thumbcache_").
  final String? filePrefix;

  /// Bu program açıksa kategori temizlenmez (ör. "chrome.exe").
  final String? processName;
  final bool requiresAdmin;

  int sizeBytes;
  int fileCount;
  String? warning;
  bool selected;

  /// true ise kullanıcı seçemez (ör. tarayıcı açık).
  bool blocked;
}

class CleanResult {
  const CleanResult({required this.freedBytes, required this.skippedFiles});
  final int freedBytes;
  final int skippedFiles;
}

// ---------------------------------------------------------------------------
// Kopya dosyalar
// ---------------------------------------------------------------------------

class DuplicateFile {
  DuplicateFile({required this.path, required this.modified, this.keep = false, this.selected = false});
  final String path;
  final DateTime modified;
  bool keep;
  bool selected;
}

/// İçeriği birebir aynı olan dosyalar.
class DuplicateGroup {
  DuplicateGroup({required this.size, required this.files});

  final int size;
  final List<DuplicateFile> files;

  String get name => baseName(files.first.path);
  int get wastedBytes => (files.length - 1) * size;
  int get selectedBytes => files.where((f) => f.selected).length * size;

  /// Verilen dosyayı korur, diğerlerini silinmek üzere seçer.
  void keepOnly(DuplicateFile kept) {
    for (final f in files) {
      f.keep = identical(f, kept);
      f.selected = !f.keep;
    }
  }
}

// ---------------------------------------------------------------------------
// Disk haritası
// ---------------------------------------------------------------------------

class FolderUsage {
  const FolderUsage({required this.name, required this.path, required this.bytes, required this.isDir});
  final String name;
  final String path;
  final int bytes;

  /// false ise içine inilemez (ör. "Bu klasördeki dosyalar", "Diğer").
  final bool isDir;
}

class StorageInfo {
  const StorageInfo({required this.total, required this.free, required this.label});
  final int total;
  final int free;
  final String label;
  double get usedRatio => total == 0 ? 0 : (total - free) / total;
}

// ---------------------------------------------------------------------------
// Başlangıç programları
// ---------------------------------------------------------------------------

enum StartupScope { user, machine }

class StartupItem {
  StartupItem({
    required this.name,
    required this.command,
    required this.scope,
    required this.fromFolder,
    required this.approvedKey,
    required this.enabled,
  });

  final String name;
  final String command;

  /// machine = tüm kullanıcılar için kayıtlı; değiştirmek yönetici izni ister.
  final StartupScope scope;

  /// true = Başlangıç klasöründeki kısayol, false = kayıt defteri girdisi.
  final bool fromFolder;

  /// Görev Yöneticisi'nin açık/kapalı bilgisini tuttuğu kayıt defteri anahtarı.
  final String approvedKey;
  bool enabled;

  /// Komuttaki çalıştırılabilir dosyanın yolu (klasörde göstermek için).
  String? get targetPath {
    final c = command.trim();
    if (c.isEmpty) return null;
    if (c.startsWith('"')) {
      final end = c.indexOf('"', 1);
      return end > 1 ? c.substring(1, end) : null;
    }
    final m = RegExp(r'^(.+?\.(exe|bat|cmd|com|lnk|url))', caseSensitive: false).firstMatch(c);
    return m?.group(1) ?? c.split(' ').first;
  }
}

// ---------------------------------------------------------------------------
// Ayarlar ve geçmiş
// ---------------------------------------------------------------------------

class HistoryEntry {
  const HistoryEntry({required this.date, required this.title, required this.bytes});

  final DateTime date;
  final String title;
  final int bytes;

  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'title': title, 'bytes': bytes};

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        title: j['title'] as String? ?? '',
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      );
}

class AppSettings {
  AppSettings({
    this.totalFreed = 0,
    this.minDuplicateSize = defaultMinDuplicateSize,
    List<String>? excluded,
    List<String>? customRoots,
    List<HistoryEntry>? history,
  })  : excluded = excluded ?? [],
        customRoots = customRoots ?? [],
        history = history ?? [];

  static const defaultMinDuplicateSize = 100 * 1024;

  /// Kurulumdan beri temizlenen toplam alan.
  int totalFreed;

  /// Kopya bulucunun dikkate aldığı en küçük dosya boyutu.
  int minDuplicateSize;

  /// Kopya bulucunun hiç girmeyeceği klasörler.
  final List<String> excluded;

  /// Kullanıcının kopya bulucuya eklediği klasörler.
  final List<String> customRoots;
  final List<HistoryEntry> history;

  Map<String, dynamic> toJson() => {
        'totalFreed': totalFreed,
        'minDuplicateSize': minDuplicateSize,
        'excluded': excluded,
        'customRoots': customRoots,
        'history': history.map((h) => h.toJson()).toList(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        totalFreed: (j['totalFreed'] as num?)?.toInt() ?? 0,
        minDuplicateSize: (j['minDuplicateSize'] as num?)?.toInt() ?? defaultMinDuplicateSize,
        excluded: (j['excluded'] as List?)?.whereType<String>().toList(),
        customRoots: (j['customRoots'] as List?)?.whereType<String>().toList(),
        history: (j['history'] as List?)?.whereType<Map<String, dynamic>>().map(HistoryEntry.fromJson).toList(),
      );
}
