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

// ---------------------------------------------------------------------------
// Uygulama kaldırıcı
// ---------------------------------------------------------------------------

class InstalledApp {
  InstalledApp({
    required this.name,
    required this.uninstallCommand,
    required this.registryKey,
    this.publisher = '',
    this.version = '',
    this.installDate,
    this.sizeBytes = 0,
    this.installLocation = '',
    this.machineWide = false,
  });

  final String name;
  final String uninstallCommand;

  /// Kayıt defterindeki anahtarı; kaldırıldı mı diye kontrol için kullanılır.
  final String registryKey;
  final String publisher;
  final String version;
  final DateTime? installDate;

  /// Programın bildirdiği boyut (0 = bilinmiyor).
  final int sizeBytes;
  final String installLocation;

  /// Tüm kullanıcılar için kurulu (kaldırırken Windows izin isteyebilir).
  final bool machineWide;
}

/// Kaldırma sonucu.
class UninstallOutcome {
  const UninstallOutcome({required this.removed, this.leftoverFolder, this.error});

  /// Program artık listede yok.
  final bool removed;

  /// Kaldırıldıktan sonra yerinde kalan kurulum klasörü.
  final String? leftoverFolder;
  final String? error;
}

// ---------------------------------------------------------------------------
// Pil ve sağlık
// ---------------------------------------------------------------------------

class BatteryInfo {
  const BatteryInfo({
    required this.name,
    required this.designCapacity,
    required this.fullChargeCapacity,
    this.cycleCount,
    this.chemistry = '',
  });

  final String name;

  /// mWh
  final int designCapacity;

  /// mWh
  final int fullChargeCapacity;
  final int? cycleCount;
  final String chemistry;

  /// Pilin ilk günkü kapasitesine göre bugünkü oranı (0-1).
  double get health => designCapacity <= 0 ? 0 : (fullChargeCapacity / designCapacity).clamp(0.0, 1.2);
}

class DiskHealth {
  const DiskHealth({
    required this.name,
    required this.mediaType,
    required this.busType,
    required this.status,
    required this.sizeBytes,
    this.temperature,
    this.wear,
    this.powerOnHours,
  });

  final String name;

  /// SSD, HDD veya boş.
  final String mediaType;
  final String busType;

  /// Healthy, Warning, Unhealthy...
  final String status;
  final int sizeBytes;
  final int? temperature;

  /// SSD yıpranma yüzdesi (0 = yeni).
  final int? wear;
  final int? powerOnHours;
}

// ---------------------------------------------------------------------------
// Medya küçültücü
// ---------------------------------------------------------------------------

class PhotoFile {
  PhotoFile({required this.path, required this.sizeBytes, this.selected = true});
  final String path;
  final int sizeBytes;
  bool selected;
}

class CompressOptions {
  const CompressOptions({this.quality = 85, this.maxDimension = 0, this.backup = true});

  /// JPEG kalitesi (1-100).
  final int quality;

  /// Uzun kenar sınırı; 0 = boyut değişmez.
  final int maxDimension;

  /// Orijinaller Geri Dönüşüm Kutusu'na taşınsın mı?
  final bool backup;
}

class CompressResult {
  const CompressResult({
    required this.compressed,
    required this.skipped,
    required this.failed,
    required this.savedBytes,
    required this.donePaths,
  });

  final int compressed;

  /// Zaten küçük olduğu için dokunulmayanlar.
  final int skipped;
  final int failed;
  final int savedBytes;

  /// Küçültülen dosyalar (listeden çıkarmak için).
  final List<String> donePaths;
}

// ---------------------------------------------------------------------------
// Konum bilgisi temizleyici
// ---------------------------------------------------------------------------

class GpsPhoto {
  GpsPhoto({required this.path, this.latitude, this.longitude, this.selected = true});
  final String path;
  final double? latitude;
  final double? longitude;
  bool selected;

  String get coordinates {
    final lat = latitude;
    final lon = longitude;
    if (lat == null || lon == null) return 'Konum kaydı var';
    return '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
  }
}

// ---------------------------------------------------------------------------
// Sistem bilgisi
// ---------------------------------------------------------------------------

class GpuInfo {
  const GpuInfo({required this.name, required this.memoryBytes});
  final String name;

  /// 0 = bilinmiyor
  final int memoryBytes;
}

/// Bir kez okunan donanım ve sistem bilgileri.
class SystemInfo {
  const SystemInfo({
    required this.cpuName,
    required this.cores,
    required this.threads,
    required this.maxMhz,
    required this.totalRam,
    required this.osName,
    required this.osBuild,
    required this.gpus,
    this.bootTime,
    this.manufacturer = '',
    this.model = '',
  });

  final String cpuName;
  final int cores;
  final int threads;
  final int maxMhz;
  final int totalRam;
  final String osName;
  final String osBuild;
  final List<GpuInfo> gpus;
  final DateTime? bootTime;
  final String manufacturer;
  final String model;
}

class ProcessMemory {
  const ProcessMemory({required this.name, required this.bytes, required this.count});
  final String name;
  final int bytes;

  /// Aynı isimli işlem sayısı (ör. tarayıcının sekmeleri).
  final int count;
}

/// Birkaç saniyede bir yenilenen canlı ölçümler.
class LiveStats {
  const LiveStats({
    required this.cpuPercent,
    required this.cpuMhz,
    required this.ramAvailable,
    this.gpuPercent,
    required this.diskRead,
    required this.diskWrite,
    required this.netDown,
    required this.netUp,
    this.temperature,
    this.topMemory = const [],
  });

  final double cpuPercent;

  /// Anlık işlemci hızı (0 = bilinmiyor).
  final int cpuMhz;
  final int ramAvailable;

  /// null = ekran kartı ölçümü yok
  final double? gpuPercent;

  /// bayt/saniye
  final int diskRead;
  final int diskWrite;
  final int netDown;
  final int netUp;

  /// Termal bölge sıcaklığı (°C). null = bu bilgisayar paylaşmıyor.
  final double? temperature;
  final List<ProcessMemory> topMemory;
}
