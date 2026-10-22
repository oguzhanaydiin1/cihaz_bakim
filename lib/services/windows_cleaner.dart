import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/i18n.dart';
import '../models/models.dart';
import 'cleaner_service.dart';
import 'fs_utils.dart';
import 'isolate_runner.dart';
import 'media_utils.dart';

/// Windows için gerçek tarama ve temizleme.
class WindowsCleaner implements CleanerService {
  final Map<String, String> _env = Platform.environment;
  bool? _admin;

  String get _local => _env['LOCALAPPDATA'] ?? '';
  String get _roaming => _env['APPDATA'] ?? '';
  String get _temp => _env['TEMP'] ?? '';
  String get _winDir => _env['SystemRoot'] ?? r'C:\Windows';
  String get _user => _env['USERPROFILE'] ?? '';
  String get _systemDrive => _env['SystemDrive'] ?? 'C:';

  static String _join(String a, String b) => a.endsWith(r'\') ? '$a$b' : '$a\\$b';

  /// PowerShell için tek tırnaklı, güvenli metin.
  static String _q(String s) => "'${s.replaceAll("'", "''")}'";

  @override
  bool get isSample => false;

  @override
  bool get supportsStartup => true;

  @override
  String get deleteDestination => L.t('Geri Dönüşüm Kutusu’na taşınacak', 'will be moved to the Recycle Bin');

  @override
  String? get settingsPath => _roaming.isEmpty ? null : _join(_roaming, r'HarrierCleaner\settings.json');

  @override
  String? get legacySettingsPath => _roaming.isEmpty ? null : _join(_roaming, r'CihazBakim\ayarlar.json');

  // ---- PowerShell yardımcıları ----

  /// PowerShell'in -EncodedCommand için beklediği biçim: UTF-16LE + base64.
  static String _encode(String script) {
    final full = '[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding \$false\n$script';
    final units = full.codeUnits;
    final bytes = Uint8List(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      bytes[i * 2] = units[i] & 0xff;
      bytes[i * 2 + 1] = units[i] >> 8;
    }
    return base64Encode(bytes);
  }

  /// Betiği -EncodedCommand ile çalıştırır: tırnak ve satır sonu kaçışı derdi olmaz.
  Future<String> _ps(String script, {Map<String, String>? env}) async {
    try {
      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', _encode(script)],
        stdoutEncoding: utf8,
        environment: env,
      );
      return (r.stdout as String).replaceAll('﻿', '').trim();
    } catch (_) {
      return '';
    }
  }

  @override
  Future<bool> isAdmin() async {
    final cached = _admin;
    if (cached != null) return cached;
    final out = await _ps(
      '([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())'
      '.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
    );
    return _admin = out.toLowerCase() == 'true';
  }

  @override
  Future<bool> relaunchAsAdmin() async {
    final out = await _ps(
      'try { Start-Process -FilePath ${_q(Platform.resolvedExecutable)} -Verb RunAs -ErrorAction Stop; "ok" } '
      'catch { "iptal" }',
    );
    if (out == 'ok') exit(0);
    return false; // kullanıcı izin penceresinde "Hayır" dedi
  }

  Future<String> _runningProcesses() async {
    try {
      final r = await Process.run('tasklist', ['/FO', 'CSV', '/NH']);
      return (r.stdout as String).toLowerCase();
    } catch (_) {
      return '';
    }
  }

  // ---- Depolama ----

  @override
  Future<StorageInfo?> storageInfo() async {
    final drive = _systemDrive.replaceAll(':', '');
    final out = await _ps(r'$d = Get-PSDrive -Name ' + drive + r'; "$($d.Used);$($d.Free)"');
    final parts = out.split(';');
    if (parts.length != 2) return null;
    final used = int.tryParse(parts[0].trim());
    final free = int.tryParse(parts[1].trim());
    if (used == null || free == null) return null;
    return StorageInfo(total: used + free, free: free, label: L.t('$_systemDrive sürücüsü dolu', '$_systemDrive drive used'));
  }

  // ---- Gereksiz dosyalar ----

  /// Chrome ve Edge gibi Chromium tabanlı tarayıcıların tüm profillerindeki önbellekler.
  List<String> _chromiumCaches(String userData) {
    final result = <String>[];
    final dir = Directory(userData);
    if (!dir.existsSync()) return result;
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final name = e.path.split(r'\').last;
        if (name == 'Default' || name.startsWith('Profile ')) {
          result.add(_join(e.path, r'Cache\Cache_Data'));
          result.add(_join(e.path, 'Code Cache'));
          result.add(_join(e.path, 'GPUCache'));
        }
      }
    } catch (_) {}
    return result;
  }

  List<String> _firefoxCaches() {
    final result = <String>[];
    final dir = Directory(_join(_local, r'Mozilla\Firefox\Profiles'));
    if (!dir.existsSync()) return result;
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is Directory) result.add(_join(e.path, 'cache2'));
      }
    } catch (_) {}
    return result;
  }

  List<JunkCategory> _categories() {
    final hasLocal = _local.isNotEmpty;
    return [
      if (_temp.isNotEmpty)
        JunkCategory(id: 'temp', name: L.t('Geçici dosyalar', 'Temporary files'), description: L.t('Kullanıcı geçici klasörü (%TEMP%)', 'User temp folder (%TEMP%)'), paths: [_temp]),
      JunkCategory(
        id: 'wintemp',
        name: L.t('Windows geçici dosyaları', 'Windows temporary files'),
        description: L.t(r'Windows\Temp klasörü', r'Windows\Temp folder'),
        paths: [_join(_winDir, 'Temp')],
        requiresAdmin: true,
      ),
      if (hasLocal)
        JunkCategory(
          id: 'chrome',
          name: L.t('Chrome önbelleği', 'Chrome cache'),
          description: L.t('Tüm Chrome profillerinin önbelleği', 'Cache of all Chrome profiles'),
          paths: _chromiumCaches(_join(_local, r'Google\Chrome\User Data')),
          processName: 'chrome.exe',
        ),
      if (hasLocal)
        JunkCategory(
          id: 'edge',
          name: L.t('Edge önbelleği', 'Edge cache'),
          description: L.t('Tüm Edge profillerinin önbelleği', 'Cache of all Edge profiles'),
          paths: _chromiumCaches(_join(_local, r'Microsoft\Edge\User Data')),
          processName: 'msedge.exe',
        ),
      if (hasLocal)
        JunkCategory(
          id: 'firefox',
          name: L.t('Firefox önbelleği', 'Firefox cache'),
          description: L.t('Tüm Firefox profillerinin önbelleği', 'Cache of all Firefox profiles'),
          paths: _firefoxCaches(),
          processName: 'firefox.exe',
        ),
      if (hasLocal)
        JunkCategory(
          id: 'thumbs',
          name: L.t('Küçük resim önbelleği', 'Thumbnail cache'),
          description: L.t('Gezgin önizleme önbelleği (bir kısmı kullanımda olabilir)', 'File Explorer preview cache (some may be in use)'),
          paths: [_join(_local, r'Microsoft\Windows\Explorer')],
          filePrefix: 'thumbcache_',
        ),
      if (hasLocal)
        JunkCategory(
          id: 'crash',
          name: L.t('Hata raporları', 'Error reports'),
          description: L.t('Çökme dökümleri ve Windows hata raporları', 'Crash dumps and Windows error reports'),
          paths: [_join(_local, 'CrashDumps'), _join(_local, r'Microsoft\Windows\WER')],
        ),
      JunkCategory(
        id: 'update',
        name: L.t('Windows Update artıkları', 'Windows Update leftovers'),
        description: L.t(r'İndirilmiş güncelleme dosyaları (SoftwareDistribution\Download)', r'Downloaded update files (SoftwareDistribution\Download)'),
        paths: [_join(_winDir, r'SoftwareDistribution\Download')],
        requiresAdmin: true,
      ),
      JunkCategory(
        id: 'recycle',
        name: L.t('Geri Dönüşüm Kutusu', 'Recycle Bin'),
        description: L.t('Silinmiş ama boşaltılmamış dosyalar', 'Deleted files that haven’t been emptied'),
        kind: JunkKind.recycleBin,
        warning: L.t('Boşaltılınca geri alınamaz', 'Can’t be undone once emptied'),
        selected: false,
      ),
    ];
  }

  @override
  Future<List<JunkCategory>?> scanJunk({ProgressReporter? onProgress, CancelToken? token}) async {
    final admin = await isAdmin();
    final running = await _runningProcesses();
    final all = _categories();

    // Klasör kategorilerini tek seferde, ayrı bir iş parçacığında ölç.
    final dirCats = <JunkCategory>[];
    final jobs = <PathJob>[];
    for (final c in all) {
      if (c.kind != JunkKind.directories) continue;
      final existing = c.paths.where((p) => Directory(p).existsSync()).toList();
      if (existing.isEmpty) continue; // ör. Firefox kurulu değil
      dirCats.add(c);
      jobs.add((existing, c.filePrefix));
    }
    final measured = await measureAll(jobs, onProgress: onProgress, token: token);
    if (measured == null) return null; // iptal edildi
    for (var i = 0; i < dirCats.length; i++) {
      dirCats[i].sizeBytes = measured[i].$1;
      dirCats[i].fileCount = measured[i].$2;
    }

    final result = <JunkCategory>[];
    for (final c in all) {
      if (c.kind == JunkKind.recycleBin) {
        onProgress?.call(const ScanProgress(phase: 'Geri Dönüşüm Kutusu okunuyor'));
        final out = await _ps(
          r'$i = (New-Object -ComObject Shell.Application).NameSpace(10).Items(); '
          r'$s = ($i | Measure-Object -Property Size -Sum).Sum; if (-not $s) { $s = 0 }; '
          r'"$([int64]$s);$($i.Count)"',
        );
        final parts = out.split(';');
        c.sizeBytes = parts.isNotEmpty ? int.tryParse(parts[0].trim()) ?? 0 : 0;
        c.fileCount = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
      } else if (!dirCats.contains(c)) {
        continue;
      }

      final proc = c.processName;
      if (proc != null && running.contains('"$proc"')) {
        c.blocked = true;
        c.selected = false;
        c.warning = L.t('Tarayıcı açık, temizlemek için kapatın', 'Browser is open, close it to clean');
      } else if (c.requiresAdmin && !admin) {
        c.selected = false;
        c.warning = L.t('Tamamı için yönetici olarak çalıştırın', 'Run as administrator to clean all of it');
      }
      if (c.sizeBytes == 0) c.selected = false;
      result.add(c);
    }
    return result;
  }

  @override
  Future<CleanResult> cleanJunk(List<JunkCategory> categories, {ProgressReporter? onProgress}) async {
    var freed = 0;
    var skipped = 0;
    final jobs = <PathJob>[];
    for (final c in categories) {
      if (c.blocked) continue;
      if (c.kind == JunkKind.recycleBin) {
        await _ps('Clear-RecycleBin -Force -ErrorAction SilentlyContinue');
        freed += c.sizeBytes;
      } else {
        jobs.add((c.paths, c.filePrefix));
      }
    }
    if (jobs.isNotEmpty) {
      final r = await cleanAll(jobs, onProgress: onProgress);
      if (r != null) {
        freed += r.$1;
        skipped += r.$2;
      }
    }
    return CleanResult(freedBytes: freed, skippedFiles: skipped);
  }

  // ---- Kopya dosyalar ----

  @override
  List<String> defaultUserFolders() {
    if (_user.isEmpty) return [];
    return ['Desktop', 'Documents', 'Downloads', 'Pictures', 'Videos', 'Music']
        .map((n) => _join(_user, n))
        .where((p) => Directory(p).existsSync())
        .toList();
  }

  @override
  Future<List<DuplicateGroup>?> findDuplicates(
    List<String> roots, {
    required int minSize,
    List<String> excluded = const [],
    ProgressReporter? onProgress,
    CancelToken? token,
  }) =>
      findDuplicatesIn(roots, minSize: minSize, excluded: excluded, onProgress: onProgress, token: token);

  /// Dosyaları kalıcı silmek yerine Geri Dönüşüm Kutusu'na taşır.
  @override
  Future<int> deleteFiles(List<String> paths) async {
    if (paths.isEmpty) return 0;
    final list = File(_join(Directory.systemTemp.path, 'harrier_cleaner_silinecek.txt'));
    await list.writeAsString(paths.join('\r\n'), encoding: utf8);
    final out = await _ps(
      r'Add-Type -AssemblyName Microsoft.VisualBasic; $n = 0; '
      'Get-Content -LiteralPath ${_q(list.path)} -Encoding UTF8 | ForEach-Object { '
      r"if ($_ -and (Test-Path -LiteralPath $_ -PathType Leaf)) { try { "
      r"[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($_, 'OnlyErrorDialogs', 'SendToRecycleBin'); $n++ "
      r'} catch {} } }; $n',
    );
    try {
      await list.delete();
    } catch (_) {}
    return int.tryParse(out) ?? 0;
  }

  // ---- Disk haritası ----

  @override
  String defaultUsageRoot() => _user.isNotEmpty ? _user : '$_systemDrive\\';

  @override
  Future<List<FolderUsage>?> folderUsage(String root, {ProgressReporter? onProgress, CancelToken? token}) =>
      folderUsageOf(root, onProgress: onProgress, token: token);

  // ---- Başlangıç programları ----

  // Görev Yöneticisi'nin "Başlangıç" sekmesiyle aynı kaynakları okur. Açık/kapalı bilgisi
  // StartupApproved anahtarında tutulur: ilk bayt çiftse açık, tekse kapalı.
  static const _startupScript = r'''
$out = New-Object System.Collections.ArrayList
function Test-Enabled($approved, $name) {
  try {
    $k = Get-Item -LiteralPath $approved -ErrorAction Stop
    $b = $k.GetValue($name)
    if ($b -is [byte[]] -and $b.Length -gt 0) { return (($b[0] -band 1) -eq 0) }
  } catch {}
  return $true
}
function Add-Run($run, $approved, $scope) {
  try { $k = Get-Item -LiteralPath $run -ErrorAction Stop } catch { return }
  foreach ($n in $k.GetValueNames()) {
    if ([string]::IsNullOrEmpty($n)) { continue }
    [void]$out.Add([pscustomobject]@{ name = $n; command = [string]$k.GetValue($n); scope = $scope; folder = $false; approved = $approved; enabled = (Test-Enabled $approved $n) })
  }
}
function Add-Folder($dir, $approved, $scope) {
  if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return }
  foreach ($f in Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue) {
    if ($f.Name -eq 'desktop.ini') { continue }
    [void]$out.Add([pscustomobject]@{ name = $f.Name; command = $f.FullName; scope = $scope; folder = $true; approved = $approved; enabled = (Test-Enabled $approved $f.Name) })
  }
}
$ua = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$ma = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
Add-Run 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' "$ua\Run" 'user'
Add-Run 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' "$ma\Run" 'machine'
Add-Run 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' "$ma\Run32" 'machine'
Add-Folder ([Environment]::GetFolderPath('Startup')) "$ua\StartupFolder" 'user'
Add-Folder ([Environment]::GetFolderPath('CommonStartup')) "$ma\StartupFolder" 'machine'
ConvertTo-Json -InputObject @($out) -Compress -Depth 3
''';

  @override
  Future<List<StartupItem>> startupItems() async {
    final out = await _ps(_startupScript);
    try {
      final data = jsonDecode(out);
      if (data is! List) return [];
      final items = <StartupItem>[];
      for (final e in data.whereType<Map<String, dynamic>>()) {
        items.add(StartupItem(
          name: e['name'] as String? ?? '',
          command: e['command'] as String? ?? '',
          scope: e['scope'] == 'machine' ? StartupScope.machine : StartupScope.user,
          fromFolder: e['folder'] == true,
          approvedKey: e['approved'] as String? ?? '',
          enabled: e['enabled'] != false,
        ));
      }
      items.sort((a, b) {
        if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Görev Yöneticisi'nin yaptığı gibi yalnızca StartupApproved değerini değiştirir;
  /// programın kaydını silmez, bu yüzden her zaman geri alınabilir.
  @override
  Future<String?> setStartupEnabled(StartupItem item, bool enabled) async {
    if (item.approvedKey.isEmpty) return L.t('Bu girdi değiştirilemiyor.', 'This entry can’t be changed.');
    final bytes = enabled
        ? '[byte[]](2,0,0,0,0,0,0,0,0,0,0,0)'
        : r'[byte[]](@(3,0,0,0) + [BitConverter]::GetBytes((Get-Date).ToFileTime()))';
    final out = await _ps(
      'try { \$p = ${_q(item.approvedKey)}; '
      'if (-not (Test-Path -LiteralPath \$p)) { New-Item -Path \$p -Force | Out-Null }; '
      'New-ItemProperty -LiteralPath \$p -Name ${_q(item.name)} -PropertyType Binary -Value $bytes -Force -ErrorAction Stop | Out-Null; '
      '"ok" } catch { "hata" }',
    );
    if (out == 'ok') return null;
    if (item.scope == StartupScope.machine && !(await isAdmin())) {
      return L.t('Bu program tüm kullanıcılar için kayıtlı. Değiştirmek için uygulamayı yönetici olarak çalıştırın.', 'This app is registered for all users. Run the app as administrator to change it.');
    }
    return L.t('Değişiklik kaydedilemedi.', 'The change couldn’t be saved.');
  }

  @override
  Future<void> revealInExplorer(String path) async {
    await _ps("Start-Process explorer.exe -ArgumentList ('/select,\"' + ${_q(path)} + '\"')");
  }

  // ---- Uygulama kaldırıcı ----

  static const _appsScript = r"""
$out = New-Object System.Collections.ArrayList
$keys = @(
  @{ p = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; m = $true },
  @{ p = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; m = $true },
  @{ p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; m = $false }
)
foreach ($k in $keys) {
  if (-not (Test-Path -LiteralPath $k.p)) { continue }
  foreach ($s in Get-ChildItem -LiteralPath $k.p -ErrorAction SilentlyContinue) {
    $v = Get-ItemProperty -LiteralPath $s.PSPath -ErrorAction SilentlyContinue
    if (-not $v) { continue }
    $name = [string]$v.DisplayName
    $un = [string]$v.UninstallString
    if (-not $name -or -not $un) { continue }
    if ($v.SystemComponent -eq 1) { continue }
    if ($v.ParentKeyName) { continue }
    if ([string]$v.ReleaseType -match 'Update|Hotfix') { continue }
    [void]$out.Add([pscustomobject]@{
      name = $name; publisher = [string]$v.Publisher; version = [string]$v.DisplayVersion
      date = [string]$v.InstallDate; size = [int64]$v.EstimatedSize; uninstall = $un
      location = [string]$v.InstallLocation; key = [string]$s.Name; machine = $k.m
    })
  }
}
ConvertTo-Json -InputObject @($out) -Compress -Depth 3
""";

  @override
  Future<List<InstalledApp>> installedApps() async {
    final out = await _ps(_appsScript);
    try {
      final data = jsonDecode(out);
      if (data is! List) return [];
      final seen = <String>{};
      final apps = <InstalledApp>[];
      for (final e in data.whereType<Map<String, dynamic>>()) {
        final name = (e['name'] as String? ?? '').trim();
        final version = e['version'] as String? ?? '';
        if (name.isEmpty || !seen.add('${name.toLowerCase()}|$version')) continue; // 32/64 bit kopyaları
        final date = e['date'] as String? ?? '';
        DateTime? installed;
        if (RegExp(r'^\d{8}$').hasMatch(date)) {
          installed = DateTime.tryParse('${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)}');
        }
        apps.add(InstalledApp(
          name: name,
          uninstallCommand: e['uninstall'] as String? ?? '',
          registryKey: e['key'] as String? ?? '',
          publisher: e['publisher'] as String? ?? '',
          version: version,
          installDate: installed,
          sizeBytes: ((e['size'] as num?)?.toInt() ?? 0) * 1024, // KB → bayt
          installLocation: (e['location'] as String? ?? '').trim().replaceAll('"', ''),
          machineWide: e['machine'] == true,
        ));
      }
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return apps;
    } catch (_) {
      return [];
    }
  }

  /// Kaldırma komutunu çalıştırılabilir dosya ve parametrelere ayırır.
  static (String, String) _splitCommand(String command) {
    final c = command.trim();
    if (c.startsWith('"')) {
      final end = c.indexOf('"', 1);
      if (end > 1) return (c.substring(1, end), c.substring(end + 1).trim());
    }
    final m = RegExp(r'^(.+?\.exe)(\s+.*)?$', caseSensitive: false).firstMatch(c);
    if (m != null) return (m.group(1)!, (m.group(2) ?? '').trim());
    final space = c.indexOf(' ');
    return space < 0 ? (c, '') : (c.substring(0, space), c.substring(space + 1).trim());
  }

  @override
  Future<String?> runUninstaller(InstalledApp app) async {
    var (file, args) = _splitCommand(app.uninstallCommand);
    // "%ProgramFiles%" gibi ortam değişkenlerini aç.
    file = file.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) => _env[m[1]!] ?? m[0]!);
    if (file.isEmpty) return L.t('Bu programın kaldırma komutu bulunamadı.', 'This program’s uninstall command wasn’t found.');
    // MSI programlarında "/I" değiştir/onar demek; kaldırmak için "/X" olmalı.
    if (file.toLowerCase().contains('msiexec')) {
      args = args.replaceAllMapped(RegExp(r'/I\s*\{', caseSensitive: false), (_) => '/X{');
    }
    final out = await _ps(
      r'try { $a = @{ FilePath = $env:HC_FILE; Wait = $true; ErrorAction = "Stop" }; '
      r'if ($env:HC_ARGS) { $a.ArgumentList = $env:HC_ARGS }; Start-Process @a; "ok" } catch { "iptal" }',
      env: {'HC_FILE': file, 'HC_ARGS': args},
    );
    return out == 'ok' ? null : L.t('Kaldırıcı başlatılamadı ya da izin penceresinde vazgeçildi.', 'The uninstaller couldn’t start, or it was cancelled at the permission prompt.');
  }

  String _norm(String p) => p.trim().replaceAll(RegExp(r'[\\/]+$'), '').toLowerCase();

  @override
  bool isSafeLeftover(String path) {
    if (!isSafeRoot(path)) return false;
    final p = _norm(path);
    final pf = _env['ProgramFiles'] ?? '';
    final pf86 = _env['ProgramFiles(x86)'] ?? '';
    final pd = _env['ProgramData'] ?? '';
    final protected = <String>{
      _winDir, pf, pf86, pd, _user, _local, _roaming,
      _join(_local, 'Programs'), _join(_local, 'Microsoft'), _join(_roaming, 'Microsoft'),
      _join(pf, 'Common Files'), _join(pf86, 'Common Files'), _join(pf, 'WindowsApps'),
      _join(_user, 'Desktop'), _join(_user, 'Documents'), _join(_user, 'Downloads'),
      '$_systemDrive\\Users',
    }.where((x) => x.isNotEmpty).map(_norm).toSet();
    if (protected.contains(p)) return false;
    if (p.startsWith('${_norm(_winDir)}\\') || p.contains('\\windowsapps')) return false;
    // Yalnızca program klasörlerinin ALTINDAKİ bir klasör silinebilir.
    final parents = [pf, pf86, pd, _local, _roaming].where((x) => x.isNotEmpty).map(_norm);
    return parents.any((a) => p.startsWith('$a\\'));
  }

  @override
  Future<bool> recycleFolder(String path) async {
    if (!isSafeLeftover(path)) return false;
    final out = await _ps(
      r'try { Add-Type -AssemblyName Microsoft.VisualBasic; '
      r'[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($env:HC_FILE, "OnlyErrorDialogs", "SendToRecycleBin"); "ok" } '
      r'catch { "hata" }',
      env: {'HC_FILE': path},
    );
    return out == 'ok';
  }

  // ---- Pil ve sağlık ----

  @override
  Future<BatteryInfo?> batteryInfo() async {
    final path = _join(Directory.systemTemp.path, 'harrier_battery.xml');
    try {
      await Process.run('powercfg', ['/batteryreport', '/xml', '/output', path]);
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}
      String text;
      if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        text = String.fromCharCodes(Uint16List.view(bytes.buffer, bytes.offsetInBytes + 2, (bytes.length - 2) ~/ 2));
      } else {
        text = utf8.decode(bytes, allowMalformed: true);
      }
      final m = RegExp(r'<Battery>(.*?)</Battery>', dotAll: true).firstMatch(text);
      if (m == null) return null;
      final block = m.group(1)!;
      String tag(String name) => RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(block)?.group(1)?.trim() ?? '';
      final design = int.tryParse(tag('DesignCapacity')) ?? 0;
      final full = int.tryParse(tag('FullChargeCapacity')) ?? 0;
      if (design <= 0 && full <= 0) return null;
      final id = tag('Id');
      return BatteryInfo(
        name: id.isNotEmpty ? id : tag('Manufacturer'),
        designCapacity: design,
        fullChargeCapacity: full,
        cycleCount: int.tryParse(tag('CycleCount')),
        chemistry: tag('Chemistry'),
      );
    } catch (_) {
      return null;
    }
  }

  static const _diskScript = r"""
$out = New-Object System.Collections.ArrayList
foreach ($d in Get-PhysicalDisk) {
  $r = $null
  try { $r = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch {}
  [void]$out.Add([pscustomobject]@{
    name = [string]$d.FriendlyName; media = [string]$d.MediaType; bus = [string]$d.BusType
    health = [string]$d.HealthStatus; size = [int64]$d.Size
    temp = $(if ($r -and $r.Temperature) { [int]$r.Temperature } else { $null })
    wear = $(if ($r -and $r.Wear -ne $null) { [int]$r.Wear } else { $null })
    hours = $(if ($r -and $r.PowerOnHours) { [int]$r.PowerOnHours } else { $null })
  })
}
ConvertTo-Json -InputObject @($out) -Compress -Depth 3
""";

  @override
  Future<List<DiskHealth>> diskHealth() async {
    final out = await _ps(_diskScript);
    try {
      final data = jsonDecode(out);
      if (data is! List) return [];
      return [
        for (final e in data.whereType<Map<String, dynamic>>())
          DiskHealth(
            name: e['name'] as String? ?? 'Disk',
            mediaType: e['media'] as String? ?? '',
            busType: e['bus'] as String? ?? '',
            status: e['health'] as String? ?? '',
            sizeBytes: (e['size'] as num?)?.toInt() ?? 0,
            temperature: (e['temp'] as num?)?.toInt(),
            wear: (e['wear'] as num?)?.toInt(),
            powerOnHours: (e['hours'] as num?)?.toInt(),
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> openBatteryReport() async {
    final path = _join(Directory.systemTemp.path, 'harrier_pil_raporu.html');
    try {
      await Process.run('powercfg', ['/batteryreport', '/output', path]);
      await _ps(r'Start-Process -FilePath $env:HC_FILE', env: {'HC_FILE': path});
    } catch (_) {}
  }

  // ---- Fotoğraflar ----

  @override
  String defaultPicturesFolder() => _picturesFolder ??= _findPicturesFolder();

  String? _picturesFolder;

  /// Resimler klasörünün gerçek yeri. OneDrive yedeklemesi açıksa Pictures klasörü
  /// "OneDrive\Resimler" gibi başka bir yere taşınmış olur; Windows bunu kayıt defterinde tutar.
  String _findPicturesFolder() {
    try {
      final r = Process.runSync('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders',
        '/v',
        'My Pictures',
      ]);
      final m = RegExp(r'My Pictures\s+REG_(?:EXPAND_)?SZ\s+(.+)').firstMatch('${r.stdout}');
      if (m != null) {
        final path = m.group(1)!.trim().replaceAllMapped(RegExp(r'%([^%]+)%'), (x) => _env[x[1]!] ?? x[0]!);
        if (Directory(path).existsSync()) return path;
      }
    } catch (_) {}
    for (final candidate in [
      if (_user.isNotEmpty) _join(_user, 'Pictures'),
      if ((_env['OneDrive'] ?? '').isNotEmpty) _join(_env['OneDrive']!, 'Pictures'),
    ]) {
      if (Directory(candidate).existsSync()) return candidate;
    }
    return defaultUsageRoot();
  }

  @override
  Future<List<PhotoFile>?> findPhotos(String root, {int minSize = 1024 * 1024, ProgressReporter? onProgress, CancelToken? token}) =>
      findLargePhotos(root, minSize, onProgress: onProgress, token: token);

  @override
  Future<CompressResult?> compressPhotos(
    List<String> paths,
    CompressOptions options, {
    ProgressReporter? onProgress,
    CancelToken? token,
  }) async {
    final r = await compressToTemp(paths, options.quality, options.maxDimension, onProgress: onProgress, token: token);
    if (r == null) {
      cleanupTemps(paths); // iptal: yarım kalan geçici dosyaları sil
      return null;
    }
    final (items, skipped, compressFailed) = r;
    var failed = compressFailed;
    var saved = 0;
    final done = <String>[];

    if (options.backup && items.isNotEmpty) {
      // Orijinalleri önce Geri Dönüşüm Kutusu'na taşı, sonra küçültülmüş halleri yerlerine koy.
      onProgress?.call(const ScanProgress(phase: 'Orijinaller Geri Dönüşüm Kutusu’na taşınıyor'));
      await deleteFiles([for (final it in items) it.$1]);
    }
    for (final (original, temp, oldSize, newSize, modifiedMs) in items) {
      final modified = DateTime.fromMillisecondsSinceEpoch(modifiedMs);
      var ok = false;
      if (options.backup) {
        if (File(original).existsSync()) {
          // Orijinal taşınamadıysa dokunma.
          try {
            File(temp).deleteSync();
          } catch (_) {}
        } else {
          try {
            File(temp).renameSync(original);
            try {
              File(original).setLastModifiedSync(modified);
            } catch (_) {}
            ok = true;
          } catch (_) {}
        }
      } else {
        ok = replaceFileSafely(original, temp, modified);
      }
      if (ok) {
        saved += oldSize - newSize;
        done.add(original);
      } else {
        failed++;
      }
    }
    return CompressResult(compressed: done.length, skipped: skipped, failed: failed, savedBytes: saved, donePaths: done);
  }

  @override
  Future<List<GpsPhoto>?> findLocationPhotos(String root, {ProgressReporter? onProgress, CancelToken? token}) =>
      findGpsPhotos(root, onProgress: onProgress, token: token);

  @override
  Future<(int, int)> removeLocation(List<String> paths, {ProgressReporter? onProgress}) async =>
      await stripGpsFrom(paths, onProgress: onProgress) ?? (0, paths.length);

  // ---- Sistem bilgisi ----

  static const _systemScript = r"""
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object { [pscustomobject]@{ name = [string]$_.Name; ram = [int64]$_.AdapterRAM } })
# AdapterRAM 4 GB'ta takılır; gerçek değer sürücü kaydında
$vr = @{}
Get-ChildItem 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | ForEach-Object {
  try {
    $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction Stop
    $v = $p.'HardwareInformation.qwMemorySize'
    if ($v -is [byte[]]) { $v = [BitConverter]::ToInt64($v, 0) }
    if ($v -and $p.DriverDesc) { $vr[[string]$p.DriverDesc] = [int64]$v }
  } catch {}
}
foreach ($g in $gpus) { if ($vr.ContainsKey($g.name)) { $g.ram = $vr[$g.name] } }
[pscustomobject]@{
  cpu = ([string]$cpu.Name).Trim(); cores = [int]$cpu.NumberOfCores; threads = [int]$cpu.NumberOfLogicalProcessors
  mhz = [int]$cpu.MaxClockSpeed; ram = [int64]$cs.TotalPhysicalMemory
  os = [string]$os.Caption; build = [string]$os.BuildNumber; boot = $os.LastBootUpTime.ToString('o')
  maker = [string]$cs.Manufacturer; model = [string]$cs.Model; gpus = $gpus
} | ConvertTo-Json -Compress -Depth 4
""";

  @override
  Future<SystemInfo?> systemInfo() async {
    final out = await _ps(_systemScript);
    try {
      final e = jsonDecode(out);
      if (e is! Map<String, dynamic>) return null;
      final gpus = <GpuInfo>[];
      final rawGpus = e['gpus'];
      if (rawGpus is List) {
        for (final g in rawGpus.whereType<Map<String, dynamic>>()) {
          gpus.add(GpuInfo(name: g['name'] as String? ?? '', memoryBytes: (g['ram'] as num?)?.toInt() ?? 0));
        }
      }
      return SystemInfo(
        cpuName: e['cpu'] as String? ?? '',
        cores: (e['cores'] as num?)?.toInt() ?? 0,
        threads: (e['threads'] as num?)?.toInt() ?? 0,
        maxMhz: (e['mhz'] as num?)?.toInt() ?? 0,
        totalRam: (e['ram'] as num?)?.toInt() ?? 0,
        osName: (e['os'] as String? ?? '').replaceFirst('Microsoft ', ''),
        osBuild: e['build'] as String? ?? '',
        bootTime: DateTime.tryParse(e['boot'] as String? ?? '')?.toLocal(),
        manufacturer: e['maker'] as String? ?? '',
        model: e['model'] as String? ?? '',
        gpus: gpus,
      );
    } catch (_) {
      return null;
    }
  }

  // Tek bir arka plan PowerShell süreci her 1,5 saniyede bir satır JSON yazar.
  // Sınıf adları WMI'dandır: Türkçe dahil her dilde aynıdır.
  // Uygulama kapanırsa (HC_PARENT süreci yoksa) kendini sonlandırır.
  static const _liveScript = r"""
$ErrorActionPreference = 'SilentlyContinue'
$parent = [int]$env:HC_PARENT
$i = 0
while ($true) {
  if (-not (Get-Process -Id $parent -ErrorAction SilentlyContinue)) { exit }
  $p = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'"
  $m = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
  $d = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"
  $n = @(Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface)
  $g = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine | Where-Object { $_.Name -like '*engtype_3D' })
  $t = @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation)
  $util = if ($p.PercentProcessorUtility -ne $null) { [double]$p.PercentProcessorUtility } else { [double]$p.PercentProcessorTime }
  $mhz = 0
  if ($p.ProcessorFrequency) { $mhz = [int]([double]$p.ProcessorFrequency * [double]$p.PercentProcessorPerformance / 100) }
  $gpu = $null
  if ($g.Count -gt 0) { $gpu = [double](($g | Measure-Object -Property UtilizationPercentage -Sum).Sum) }
  $temp = $null
  foreach ($z in $t) {
    $k = if ($z.HighPrecisionTemperature) { [double]$z.HighPrecisionTemperature / 10 } else { [double]$z.Temperature }
    $c = $k - 273.15
    if ($c -gt 5 -and $c -lt 125 -and ($temp -eq $null -or $c -gt $temp)) { $temp = [math]::Round($c, 1) }
  }
  $top = $null
  if ($i % 3 -eq 0) {
    $top = @(Get-Process | Group-Object ProcessName | ForEach-Object {
      [pscustomobject]@{ n = $_.Name; b = [int64](($_.Group | Measure-Object WorkingSet64 -Sum).Sum); c = $_.Count }
    } | Sort-Object b -Descending | Select-Object -First 6)
  }
  $o = [ordered]@{
    cpu = $util; mhz = $mhz; avail = [int64]$m.AvailableBytes; gpu = $gpu
    dr = [int64]$d.DiskReadBytesPersec; dw = [int64]$d.DiskWriteBytesPersec
    nd = [int64](($n | Measure-Object -Property BytesReceivedPersec -Sum).Sum)
    nu = [int64](($n | Measure-Object -Property BytesSentPersec -Sum).Sum)
    temp = $temp; top = $top
  }
  [Console]::Out.WriteLine((ConvertTo-Json -InputObject $o -Compress -Depth 4))
  [Console]::Out.Flush()
  $i++
  Start-Sleep -Milliseconds 1500
}
""";

  @override
  Stream<LiveStats> liveStats() {
    Process? process;
    StreamSubscription<String>? lines;
    var cancelled = false;
    var lastTop = const <ProcessMemory>[];
    late final StreamController<LiveStats> controller;
    controller = StreamController<LiveStats>(
      onListen: () async {
        try {
          final p = await Process.start(
            'powershell',
            ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', _encode(_liveScript)],
            environment: {'HC_PARENT': '$pid'},
          );
          if (cancelled) {
            p.kill();
            return;
          }
          process = p;
          lines = p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
            final stats = _parseLive(line, lastTop);
            if (stats != null && !controller.isClosed) {
              lastTop = stats.topMemory;
              controller.add(stats);
            }
          });
        } catch (e) {
          if (!controller.isClosed) controller.addError(e);
        }
      },
      onCancel: () async {
        cancelled = true;
        await lines?.cancel();
        process?.kill();
      },
    );
    return controller.stream;
  }

  static LiveStats? _parseLive(String line, List<ProcessMemory> previousTop) {
    try {
      final e = jsonDecode(line);
      if (e is! Map<String, dynamic>) return null;
      double d(String k) => (e[k] as num?)?.toDouble() ?? 0;
      int i(String k) => (e[k] as num?)?.toInt() ?? 0;
      var top = previousTop;
      final rawTop = e['top'];
      if (rawTop is List) {
        top = [
          for (final t in rawTop.whereType<Map<String, dynamic>>())
            ProcessMemory(
              name: t['n'] as String? ?? '',
              bytes: (t['b'] as num?)?.toInt() ?? 0,
              count: (t['c'] as num?)?.toInt() ?? 1,
            ),
        ];
      }
      final gpu = e['gpu'] as num?;
      final temp = e['temp'] as num?;
      return LiveStats(
        cpuPercent: d('cpu').clamp(0.0, 100.0),
        cpuMhz: i('mhz'),
        ramAvailable: i('avail'),
        gpuPercent: gpu?.toDouble().clamp(0.0, 100.0),
        diskRead: i('dr'),
        diskWrite: i('dw'),
        netDown: i('nd'),
        netUp: i('nu'),
        temperature: temp?.toDouble(),
        topMemory: top,
      );
    } catch (_) {
      return null;
    }
  }

  // ---- İzin kontrolü ----

  // Windows, kamera/mikrofon/konum erişimlerini ConsentStore anahtarında tutar:
  // Value = Allow/Deny, LastUsedTimeStart/Stop = son kullanımın başlangıç ve bitişi (FILETIME).
  static const _permissionScript = r"""
$out = New-Object System.Collections.ArrayList
$base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
function Add-App($cap, $key, $display, $store) {
  $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
  if (-not $p) { return }
  [void]$out.Add([pscustomobject]@{
    cap = $cap; kind = $(if ($store) { 'store' } else { 'desktop' }); name = $display
    value = [string]$p.Value; start = [int64]$p.LastUsedTimeStart; stop = [int64]$p.LastUsedTimeStop
  })
}
foreach ($cap in @('webcam', 'microphone', 'location')) {
  $root = Join-Path $base $cap
  if (-not (Test-Path -LiteralPath $root)) { continue }
  $g = Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue
  [void]$out.Add([pscustomobject]@{ cap = $cap; kind = 'global'; name = ''; value = [string]$g.Value; start = 0; stop = 0 })
  foreach ($k in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
    if ($k.PSChildName -eq 'NonPackaged') {
      foreach ($d in Get-ChildItem -LiteralPath $k.PSPath -ErrorAction SilentlyContinue) {
        Add-App $cap $d ($d.PSChildName -replace '#', '\') $false
      }
    } else {
      Add-App $cap $k $k.PSChildName $true
    }
  }
}
ConvertTo-Json -InputObject @($out) -Compress -Depth 3
""";

  static DateTime? _fileTime(int ft) {
    if (ft <= 0) return null;
    return DateTime.fromMicrosecondsSinceEpoch(ft ~/ 10 - 11644473600000000, isUtc: true).toLocal();
  }

  /// "Microsoft.WindowsCamera_8wekyb3d8bbwe" → "WindowsCamera"
  static String _storeName(String package) {
    var n = package.split('_').first;
    if (n.startsWith('Microsoft.')) n = n.substring('Microsoft.'.length);
    return n;
  }

  @override
  Future<PermissionOverview?> permissions() async {
    final out = await _ps(_permissionScript);
    try {
      final data = jsonDecode(out);
      if (data is! List) return null;
      const caps = {'webcam': PermissionKind.camera, 'microphone': PermissionKind.microphone, 'location': PermissionKind.location};
      final enabled = <PermissionKind, bool?>{};
      final uses = <PermissionUse>[];
      for (final e in data.whereType<Map<String, dynamic>>()) {
        final kind = caps[e['cap']];
        if (kind == null) continue;
        final value = (e['value'] as String? ?? '').toLowerCase();
        if (e['kind'] == 'global') {
          enabled[kind] = value.isEmpty ? null : value != 'deny';
          continue;
        }
        final name = e['name'] as String? ?? '';
        if (name.isEmpty) continue;
        final store = e['kind'] == 'store';
        final start = (e['start'] as num?)?.toInt() ?? 0;
        final stop = (e['stop'] as num?)?.toInt() ?? 0;
        uses.add(PermissionUse(
          kind: kind,
          appName: store ? _storeName(name) : name.split(r'\').last,
          detail: name,
          storeApp: store,
          allowed: value != 'deny',
          lastUsed: _fileTime(start > stop ? start : stop),
          inUse: start > 0 && start > stop,
        ));
      }
      uses.sort((a, b) {
        if (a.inUse != b.inUse) return a.inUse ? -1 : 1;
        final la = a.lastUsed?.millisecondsSinceEpoch ?? 0;
        final lb = b.lastUsed?.millisecondsSinceEpoch ?? 0;
        return lb.compareTo(la);
      });
      return PermissionOverview(enabled: enabled, uses: uses);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openPrivacySettings(PermissionKind kind) async {
    final page = switch (kind) {
      PermissionKind.camera => 'privacy-webcam',
      PermissionKind.microphone => 'privacy-microphone',
      PermissionKind.location => 'privacy-location',
    };
    await _ps(r'Start-Process -FilePath $env:HC_FILE', env: {'HC_FILE': 'ms-settings:$page'});
  }

  // ---- Genel ----

  @override
  Future<void> openUrl(String url) async {
    if (!(url.startsWith('https://') || url.startsWith('mailto:'))) return;
    await _ps(r'Start-Process -FilePath $env:HC_FILE', env: {'HC_FILE': url});
  }

  @override
  String? get errorLogPath => _roaming.isEmpty ? null : _join(_roaming, r'HarrierCleaner\errors.log');
}
