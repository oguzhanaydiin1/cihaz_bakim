import 'package:flutter/material.dart';

import 'platform.dart';

enum ModuleId {
  smartScan,
  junk,
  duplicates,
  diskMap,
  media,
  screenshots,
  apps,
  startup,
  health,
  permissions,
  metadata,
  shredder,
  organizer,
  settings,
}

enum Availability { both, windowsOnly, androidOnly }

class ModuleInfo {
  const ModuleInfo({
    required this.id,
    required this.group,
    required this.name,
    required this.icon,
    required this.version,
    this.availability = Availability.both,
    this.description = '',
    this.plan = const [],
  });

  final ModuleId id;
  final String group;
  final String name;
  final IconData icon;

  /// Modülün geleceği sürüm. 1 = ilk sürümde çalışıyor.
  final int version;
  final Availability availability;
  final String description;
  final List<String> plan;

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
  ModuleInfo(id: ModuleId.smartScan, group: 'Genel', name: 'Akıllı Tarama', icon: Icons.manage_search, version: 1),
  ModuleInfo(id: ModuleId.junk, group: 'Depolama', name: 'Gereksiz Dosyalar', icon: Icons.delete_outline, version: 1),
  ModuleInfo(id: ModuleId.duplicates, group: 'Depolama', name: 'Kopya Dosyalar', icon: Icons.file_copy_outlined, version: 1),
  ModuleInfo(id: ModuleId.diskMap, group: 'Depolama', name: 'Disk Haritası', icon: Icons.dashboard_outlined, version: 1),
  ModuleInfo(
    id: ModuleId.media,
    group: 'Depolama',
    name: 'Medya Küçültücü',
    icon: Icons.photo_size_select_large,
    version: 1,
    description: 'Fotoğraf ve videoları kaliteyi gözle görülür düşürmeden sıkıştırır.',
    plan: ['Toplu sıkıştırma, önce/sonra karşılaştırma', 'Orijinali yedekleme seçeneği', 'Videolarda çözünürlük düşürme'],
  ),
  ModuleInfo(
    id: ModuleId.screenshots,
    group: 'Depolama',
    name: 'Ekran Görüntüleri',
    icon: Icons.screenshot_outlined,
    version: 2,
    availability: Availability.androidOnly,
    description: 'Biriken ekran görüntülerini kaydırarak hızlıca gözden geçirip silmenizi sağlar.',
    plan: ['Sağa kaydır: tut, sola kaydır: sil', '30 günden eski görüntüleri toplu seçme', 'Metin içeren görüntüleri ayırma'],
  ),
  ModuleInfo(
    id: ModuleId.apps,
    group: 'Sistem',
    name: 'Uygulama Kaldırıcı',
    icon: Icons.apps,
    version: 1,
    description: 'Uygulamaları boyutuna ve son kullanım tarihine göre listeler.',
    plan: [
      'Uzun süredir açılmayan uygulamaları öne çıkarma',
      'Windows: kaldırma sonrası kalan artıkları temizleme',
      'Android: ilgili uygulamanın depolama ayarına yönlendirme',
    ],
  ),
  ModuleInfo(
    id: ModuleId.startup,
    group: 'Sistem',
    name: 'Başlangıç Programları',
    icon: Icons.power_settings_new,
    version: 1,
    availability: Availability.windowsOnly,
  ),
  ModuleInfo(
    id: ModuleId.health,
    group: 'Sistem',
    name: 'Pil ve Sağlık',
    icon: Icons.battery_std,
    version: 1,
    description: 'Pil yıpranması, disk sağlığı ve sıcaklık bilgilerini tek ekranda gösterir.',
    plan: ['Pil kapasitesinin ilk günle karşılaştırması', 'Disk SMART durumu (Windows)', 'Pili en çok tüketen uygulamalar (Android)'],
  ),
  ModuleInfo(
    id: ModuleId.permissions,
    group: 'Gizlilik',
    name: 'İzin Kontrolü',
    icon: Icons.shield_outlined,
    version: 3,
    description: 'Hangi uygulamanın konum, kamera ve mikrofon izni olduğunu gösterir.',
    plan: ['İzinleri uygulamaya ve izin türüne göre listeleme', 'Son kullanım zamanı', 'Ayarlara tek dokunuşla gitme'],
  ),
  ModuleInfo(
    id: ModuleId.metadata,
    group: 'Gizlilik',
    name: 'Konum Bilgisi Temizleyici',
    icon: Icons.location_off_outlined,
    version: 1,
    description: 'Fotoğrafları paylaşmadan önce içindeki konum ve cihaz bilgilerini siler.',
    plan: ['Toplu temizleme', 'Paylaşım menüsünden doğrudan kullanım (Android)', 'Sağ tık menüsü entegrasyonu (Windows)'],
  ),
  ModuleInfo(
    id: ModuleId.shredder,
    group: 'Gizlilik',
    name: 'Güvenli Silici',
    icon: Icons.lock_outline,
    version: 3,
    availability: Availability.windowsOnly,
    description: 'Hassas dosyaları geri getirilemeyecek şekilde siler.',
    plan: ['Sürükle bırak ile silme', 'SSD için uygun silme yöntemi', 'Geri Dönüşüm Kutusu’nu güvenli boşaltma'],
  ),
  ModuleInfo(
    id: ModuleId.organizer,
    group: 'Düzen',
    name: 'Klasör Düzenleyici',
    icon: Icons.folder_outlined,
    version: 3,
    description: 'İndirilenler klasörünü dosya türüne ve tarihe göre otomatik düzenler.',
    plan: ['Kural tanımlama (ör. PDF’ler → Belgeler)', 'Zamanlanmış otomatik çalışma', 'Her işlemi geri alabilme'],
  ),
  ModuleInfo(id: ModuleId.settings, group: 'Uygulama', name: 'Ayarlar', icon: Icons.settings_outlined, version: 1),
];

ModuleInfo moduleById(ModuleId id) => modules.firstWhere((m) => m.id == id);
