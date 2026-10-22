import 'package:flutter/material.dart';

import 'i18n.dart';
import 'platform.dart';

enum ModuleId {
  smartScan,
  junk,
  duplicates,
  diskMap,
  media,
  screenshots,
  system,
  apps,
  startup,
  health,
  permissions,
  metadata,
  shredder,
  organizer,
  settings,
  support,
  about,
}

enum Availability { both, windowsOnly, androidOnly }

/// Menü grupları, iki dilde.
enum ModuleGroup {
  general('Genel', 'General'),
  storage('Depolama', 'Storage'),
  system('Sistem', 'System'),
  privacy('Gizlilik', 'Privacy'),
  organize('Düzen', 'Organize'),
  app('Uygulama', 'App');

  const ModuleGroup(this.tr, this.en);
  final String tr;
  final String en;
  String get label => L.t(tr, en);
}

class ModuleInfo {
  const ModuleInfo({
    required this.id,
    required this.group,
    required this.nameTr,
    required this.nameEn,
    required this.icon,
    required this.version,
    this.availability = Availability.both,
    this.descTr = '',
    this.descEn = '',
    this.planTr = const [],
    this.planEn = const [],
  });

  final ModuleId id;
  final ModuleGroup group;
  final String nameTr;
  final String nameEn;
  final IconData icon;

  /// Modülün geleceği sürüm. 1 = ilk sürümde çalışıyor.
  final int version;
  final Availability availability;
  final String descTr;
  final String descEn;
  final List<String> planTr;
  final List<String> planEn;

  String get name => L.t(nameTr, nameEn);
  String get description => L.t(descTr, descEn);
  List<String> get plan => L.isTr ? planTr : planEn;

  bool get isReady => version == 1;

  bool isAvailableOn(AppPlatform p) {
    switch (availability) {
      case Availability.both:
        return true;
      case Availability.windowsOnly:
        return p != AppPlatform.android;
      case Availability.androidOnly:
        return p == AppPlatform.android;
    }
  }
}

const modules = <ModuleInfo>[
  ModuleInfo(
    id: ModuleId.smartScan,
    group: ModuleGroup.general,
    nameTr: 'Akıllı Tarama',
    nameEn: 'Smart Scan',
    icon: Icons.manage_search,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.junk,
    group: ModuleGroup.storage,
    nameTr: 'Gereksiz Dosyalar',
    nameEn: 'Junk Files',
    icon: Icons.delete_outline,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.duplicates,
    group: ModuleGroup.storage,
    nameTr: 'Kopya Dosyalar',
    nameEn: 'Duplicate Files',
    icon: Icons.file_copy_outlined,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.diskMap,
    group: ModuleGroup.storage,
    nameTr: 'Disk Haritası',
    nameEn: 'Disk Map',
    icon: Icons.dashboard_outlined,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.media,
    group: ModuleGroup.storage,
    nameTr: 'Medya Küçültücü',
    nameEn: 'Photo Compressor',
    icon: Icons.photo_size_select_large,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.screenshots,
    group: ModuleGroup.storage,
    nameTr: 'Ekran Görüntüleri',
    nameEn: 'Screenshots',
    icon: Icons.screenshot_outlined,
    version: 2,
    availability: Availability.androidOnly,
    descTr: 'Biriken ekran görüntülerini kaydırarak hızlıca gözden geçirip silmenizi sağlar.',
    descEn: 'Swipe through piled-up screenshots and delete the ones you don’t need.',
    planTr: ['Sağa kaydır: tut, sola kaydır: sil', '30 günden eski görüntüleri toplu seçme', 'Metin içeren görüntüleri ayırma'],
    planEn: ['Swipe right to keep, left to delete', 'Select screenshots older than 30 days at once', 'Separate screenshots that contain text'],
  ),
  ModuleInfo(
    id: ModuleId.system,
    group: ModuleGroup.system,
    nameTr: 'Sistem Bilgisi',
    nameEn: 'System Info',
    icon: Icons.memory,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.apps,
    group: ModuleGroup.system,
    nameTr: 'Uygulama Kaldırıcı',
    nameEn: 'Uninstaller',
    icon: Icons.apps,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.startup,
    group: ModuleGroup.system,
    nameTr: 'Başlangıç Programları',
    nameEn: 'Startup Apps',
    icon: Icons.power_settings_new,
    version: 1,
    availability: Availability.windowsOnly,
  ),
  ModuleInfo(
    id: ModuleId.health,
    group: ModuleGroup.system,
    nameTr: 'Pil ve Sağlık',
    nameEn: 'Battery & Health',
    icon: Icons.battery_std,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.permissions,
    group: ModuleGroup.privacy,
    nameTr: 'İzin Kontrolü',
    nameEn: 'App Permissions',
    icon: Icons.shield_outlined,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.metadata,
    group: ModuleGroup.privacy,
    nameTr: 'Konum Bilgisi Temizleyici',
    nameEn: 'Photo Location Remover',
    icon: Icons.location_off_outlined,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.shredder,
    group: ModuleGroup.privacy,
    nameTr: 'Güvenli Silici',
    nameEn: 'Secure Delete',
    icon: Icons.lock_outline,
    version: 3,
    availability: Availability.windowsOnly,
    descTr: 'Hassas dosyaları geri getirilemeyecek şekilde siler.',
    descEn: 'Deletes sensitive files so they can’t be recovered.',
    planTr: ['Sürükle bırak ile silme', 'SSD için uygun silme yöntemi', 'Geri Dönüşüm Kutusu’nu güvenli boşaltma'],
    planEn: ['Drag and drop to delete', 'A deletion method suited to SSDs', 'Securely empty the Recycle Bin'],
  ),
  ModuleInfo(
    id: ModuleId.organizer,
    group: ModuleGroup.organize,
    nameTr: 'Klasör Düzenleyici',
    nameEn: 'Folder Organizer',
    icon: Icons.folder_outlined,
    version: 3,
    descTr: 'İndirilenler klasörünü dosya türüne ve tarihe göre otomatik düzenler.',
    descEn: 'Automatically sorts your Downloads folder by file type and date.',
    planTr: ['Kural tanımlama (ör. PDF’ler → Belgeler)', 'Zamanlanmış otomatik çalışma', 'Her işlemi geri alabilme'],
    planEn: ['Your own rules (e.g. PDFs → Documents)', 'Runs automatically on a schedule', 'Every change can be undone'],
  ),
  ModuleInfo(
    id: ModuleId.settings,
    group: ModuleGroup.app,
    nameTr: 'Ayarlar',
    nameEn: 'Settings',
    icon: Icons.settings_outlined,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.support,
    group: ModuleGroup.app,
    nameTr: 'İletişim ve Destek',
    nameEn: 'Help & Contact',
    icon: Icons.support_agent,
    version: 1,
  ),
  ModuleInfo(
    id: ModuleId.about,
    group: ModuleGroup.app,
    nameTr: 'Hakkında',
    nameEn: 'About',
    icon: Icons.info_outline,
    version: 1,
  ),
];

ModuleInfo moduleById(ModuleId id) => modules.firstWhere((m) => m.id == id);
