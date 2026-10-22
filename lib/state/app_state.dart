import 'package:flutter/widgets.dart';

import '../core/modules.dart';
import '../models/models.dart';
import '../services/cleaner_service.dart';
import '../services/isolate_runner.dart';
import '../services/settings_store.dart';

/// Uygulamanın tüm durumu. Ekranlar AppScope.of(context) ile erişir.
class AppState extends ChangeNotifier {
  AppState(this.service)
      : store = SettingsStore(service.settingsPath),
        knownRoots = service.defaultUserFolders().toList(),
        dupeRoots = service.defaultUserFolders().toList(),
        usageRoot = service.defaultUsageRoot();

  final CleanerService service;
  final SettingsStore store;
  AppSettings settings = AppSettings();

  /// Uygulama yönetici izniyle mi çalışıyor? (null = henüz bilinmiyor)
  bool? admin;
  StorageInfo? storage;

  Future<void> init() async {
    settings = await store.load();
    final defaults = service.defaultUserFolders();
    knownRoots
      ..clear()
      ..addAll(defaults)
      ..addAll(settings.customRoots.where((r) => !defaults.contains(r)));
    dupeRoots
      ..clear()
      ..addAll(knownRoots);
    notifyListeners();
    storage = await service.storageInfo();
    admin = await service.isAdmin();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Gezinme
  // ---------------------------------------------------------------------------

  ModuleId current = ModuleId.smartScan;

  void open(ModuleId id) {
    current = id;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Süren işlem: ilerleme ve iptal
  // ---------------------------------------------------------------------------

  /// Şu an süren taramanın anlık durumu.
  ScanProgress? progress;
  CancelToken? _token;

  bool get canCancel => _token != null;

  /// Aynı anda yalnızca bir uzun işlem çalışır.
  bool get anyBusy => scanning || junkBusy || dupesBusy || usageBusy;

  void cancel() => _token?.cancel();

  CancelToken _begin() {
    final t = CancelToken();
    _token = t;
    progress = const ScanProgress();
    return t;
  }

  void _end(CancelToken t) {
    if (identical(_token, t)) {
      _token = null;
      progress = null;
    }
  }

  void _onProgress(ScanProgress p) {
    progress = p;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Akıllı tarama
  // ---------------------------------------------------------------------------

  bool scanning = false;
  double scanStage = 0;
  String scanStep = '';
  DateTime? lastScan;

  void _stage(String text, double stage) {
    scanStep = text;
    scanStage = stage;
    progress = const ScanProgress();
    notifyListeners();
  }

  Future<void> smartScan() async {
    if (anyBusy) return;
    scanning = true;
    final t = _begin();
    const cancelled = 'Tarama iptal edildi.';
    try {
      _stage('Depolama bilgisi okunuyor…', 0.02);
      storage = await service.storageInfo();

      _stage('Gereksiz dosyalar taranıyor…', 0.1);
      final j = await service.scanJunk(onProgress: _onProgress, token: t);
      if (j == null) {
        scanStep = cancelled;
        return;
      }
      junk = j;

      _stage('Kopya dosyalar aranıyor…', 0.35);
      final d = await service.findDuplicates(
        dupeRoots,
        minSize: settings.minDuplicateSize,
        excluded: settings.excluded,
        onProgress: _onProgress,
        token: t,
      );
      if (d == null) {
        scanStep = cancelled;
        return;
      }
      dupes = d;

      _stage('Klasör boyutları hesaplanıyor…', 0.7);
      final u = await service.folderUsage(usageRoot, onProgress: _onProgress, token: t);
      if (u == null) {
        scanStep = cancelled;
        return;
      }
      usage = u;

      if (service.supportsStartup) {
        _stage('Başlangıç programları okunuyor…', 0.95);
        startup = await service.startupItems();
      }

      lastScan = DateTime.now();
      scanStep = '';
      scanStage = 1;
    } catch (e) {
      scanStep = 'Tarama sırasında bir hata oluştu: $e';
    } finally {
      scanning = false;
      _end(t);
      notifyListeners();
    }
  }

  /// Akıllı tarama özetindeki "açılabilir alan".
  int get reclaimableBytes => selectedJunkBytes + selectedDupeBytes;

  int get totalFreed => settings.totalFreed;

  Future<void> _record(String title, int bytes) async {
    if (bytes <= 0) return;
    settings.totalFreed += bytes;
    settings.history.insert(0, HistoryEntry(date: DateTime.now(), title: title, bytes: bytes));
    if (settings.history.length > 50) settings.history.removeRange(50, settings.history.length);
    await store.save(settings);
  }

  // ---------------------------------------------------------------------------
  // Gereksiz dosyalar
  // ---------------------------------------------------------------------------

  List<JunkCategory>? junk;
  bool junkBusy = false;

  Future<void> scanJunk() async {
    if (anyBusy) return;
    junkBusy = true;
    final t = _begin();
    notifyListeners();
    try {
      final r = await service.scanJunk(onProgress: _onProgress, token: t);
      if (r != null) junk = r;
    } finally {
      junkBusy = false;
      _end(t);
      notifyListeners();
    }
  }

  void toggleJunk(JunkCategory c) {
    if (c.blocked) return;
    c.selected = !c.selected;
    notifyListeners();
  }

  int get selectedJunkBytes =>
      (junk ?? []).where((c) => c.selected && !c.blocked).fold<int>(0, (s, c) => s + c.sizeBytes);

  Future<CleanResult> cleanSelectedJunk() async {
    final selected = (junk ?? []).where((c) => c.selected && !c.blocked).toList();
    junkBusy = true;
    final t = _begin();
    notifyListeners();
    try {
      final result = await service.cleanJunk(selected, onProgress: _onProgress);
      await _record('Gereksiz dosya temizliği', result.freedBytes);
      _end(t);
      _token = _begin(); // yeniden tarama da iptal edilebilsin
      final again = await service.scanJunk(onProgress: _onProgress, token: _token);
      if (again != null) junk = again;
      storage = await service.storageInfo();
      return result;
    } finally {
      junkBusy = false;
      final token = _token;
      if (token != null) _end(token);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Kopya dosyalar
  // ---------------------------------------------------------------------------

  final List<String> knownRoots;
  final List<String> dupeRoots;
  List<DuplicateGroup>? dupes;
  bool dupesBusy = false;

  bool isCustomRoot(String path) => settings.customRoots.contains(path);

  void toggleRoot(String path) {
    if (dupeRoots.contains(path)) {
      dupeRoots.remove(path);
    } else {
      dupeRoots.add(path);
    }
    notifyListeners();
  }

  Future<void> addRoot(String path) async {
    final p = path.trim();
    if (p.isEmpty) return;
    if (!knownRoots.contains(p)) knownRoots.add(p);
    if (!dupeRoots.contains(p)) dupeRoots.add(p);
    if (!settings.customRoots.contains(p) && !service.defaultUserFolders().contains(p)) {
      settings.customRoots.add(p);
      await store.save(settings);
    }
    notifyListeners();
  }

  Future<void> removeRoot(String path) async {
    knownRoots.remove(path);
    dupeRoots.remove(path);
    settings.customRoots.remove(path);
    await store.save(settings);
    notifyListeners();
  }

  Future<void> scanDuplicates() async {
    if (anyBusy) return;
    dupesBusy = true;
    final t = _begin();
    notifyListeners();
    try {
      final r = await service.findDuplicates(
        dupeRoots,
        minSize: settings.minDuplicateSize,
        excluded: settings.excluded,
        onProgress: _onProgress,
        token: t,
      );
      if (r != null) dupes = r;
    } finally {
      dupesBusy = false;
      _end(t);
      notifyListeners();
    }
  }

  void toggleDuplicate(DuplicateFile f) {
    if (f.keep) return;
    f.selected = !f.selected;
    notifyListeners();
  }

  void keepDuplicate(DuplicateGroup g, DuplicateFile f) {
    g.keepOnly(f);
    notifyListeners();
  }

  int get selectedDupeBytes => (dupes ?? []).fold<int>(0, (s, g) => s + g.selectedBytes);

  /// Seçili kopyaları siler. Silinen dosya sayısını döndürür.
  Future<int> deleteSelectedDuplicates() async {
    final groups = dupes ?? [];
    final paths = [for (final g in groups) ...g.files.where((f) => f.selected).map((f) => f.path)];
    if (paths.isEmpty) return 0;
    final bytes = selectedDupeBytes;
    dupesBusy = true;
    notifyListeners();
    try {
      final deleted = await service.deleteFiles(paths);
      if (deleted > 0) {
        // Kısmen silindiyse yaklaşık değer: silinen oranında.
        await _record('Kopya dosyalar silindi', (bytes * deleted / paths.length).round());
      }
      for (final g in groups) {
        g.files.removeWhere((f) => f.selected);
      }
      groups.removeWhere((g) => g.files.length < 2);
      storage = await service.storageInfo();
      return deleted;
    } finally {
      dupesBusy = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Disk haritası
  // ---------------------------------------------------------------------------

  String usageRoot;
  List<FolderUsage>? usage;
  bool usageBusy = false;

  Future<void> loadUsage([String? root]) async {
    if (anyBusy) return;
    final previous = usageRoot;
    if (root != null) usageRoot = root;
    usageBusy = true;
    final t = _begin();
    notifyListeners();
    try {
      final r = await service.folderUsage(usageRoot, onProgress: _onProgress, token: t);
      if (r != null) {
        usage = r;
      } else {
        usageRoot = previous; // iptal: önceki klasörde kal
      }
    } finally {
      usageBusy = false;
      _end(t);
      notifyListeners();
    }
  }

  String? get usageParent {
    final p = usageRoot.replaceAll(RegExp(r'[\\/]+$'), '');
    final i = p.lastIndexOf(RegExp(r'[\\/]'));
    if (i <= 0) return null;
    final parent = p.substring(0, i);
    // "C:" gibi bir sürücü kökünde kalırsak sonuna ayırıcı ekle.
    return parent.endsWith(':') ? '$parent\\' : parent;
  }

  // ---------------------------------------------------------------------------
  // Başlangıç programları
  // ---------------------------------------------------------------------------

  List<StartupItem>? startup;
  bool startupBusy = false;

  Future<void> loadStartup() async {
    if (startupBusy) return;
    startupBusy = true;
    notifyListeners();
    try {
      startup = await service.startupItems();
    } finally {
      startupBusy = false;
      notifyListeners();
    }
  }

  /// Başarılıysa null, değilse hata mesajı döndürür.
  Future<String?> toggleStartup(StartupItem item) async {
    final target = !item.enabled;
    final error = await service.setStartupEnabled(item, target);
    if (error == null) item.enabled = target;
    notifyListeners();
    return error;
  }

  // ---------------------------------------------------------------------------
  // Ayarlar
  // ---------------------------------------------------------------------------

  Future<void> setMinDuplicateSize(int bytes) async {
    settings.minDuplicateSize = bytes;
    notifyListeners();
    await store.save(settings);
  }

  Future<void> addExcluded(String path) async {
    final p = path.trim();
    if (p.isEmpty || settings.excluded.contains(p)) return;
    settings.excluded.add(p);
    notifyListeners();
    await store.save(settings);
  }

  Future<void> removeExcluded(String path) async {
    settings.excluded.remove(path);
    notifyListeners();
    await store.save(settings);
  }

  Future<void> clearHistory() async {
    settings.history.clear();
    notifyListeners();
    await store.save(settings);
  }

  /// Başarılı olursa uygulama kapanıp yönetici olarak yeniden açılır.
  Future<bool> relaunchAsAdmin() => service.relaunchAsAdmin();
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  /// Değişiklikleri dinleyerek erişir (build içinde kullanın).
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Dinlemeden erişir (olay işleyicilerinde kullanın).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
