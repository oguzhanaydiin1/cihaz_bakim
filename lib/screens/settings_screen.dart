import 'dart:io';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/updater.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/folder_picker.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _sizes = <int>[1024, 100 * 1024, 1024 * 1024, 10 * 1024 * 1024];

  Future<void> _addExcluded(AppState state) async {
    final path = await pickFolder(L.t('Kopya bulucunun atlayacağı klasörü seçin', 'Choose a folder for the duplicate finder to skip'));
    if (path != null) await state.addExcluded(path);
  }

  Future<void> _clearHistory(BuildContext context, AppState state) async {
    final ok = await confirm(
      context,
      title: L.t('Geçmiş silinsin mi?', 'Clear history?'),
      message: L.t(
        'Temizlik geçmişi listesi silinir. Toplam temizlenen alan bilgisi korunur.',
        'The cleanup history list is cleared. The total space freed is kept.',
      ),
      action: L.t('Sil', 'Clear'),
    );
    if (ok) await state.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    final selectedSize = _sizes.contains(s.minDuplicateSize) ? s.minDuplicateSize : _sizes[1];
    final admin = state.admin;

    return ModulePage(
      title: L.t('Ayarlar', 'Settings'),
      subtitle: L.t(
        'Tercihleriniz ve temizlik geçmişiniz bu bilgisayarda saklanır.',
        'Your preferences and cleanup history are stored on this computer.',
      ),
      children: [
        if (state.service.isSample) const SampleBanner(),

        // ---- Genel ----
        _Section(
          title: L.t('Genel', 'General'),
          children: [
            Text(L.t('Dil', 'Language'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<AppLanguage>(
              segments: [
                ButtonSegment(value: AppLanguage.system, label: Text(L.t('Sistem dili', 'System'))),
                const ButtonSegment(value: AppLanguage.tr, label: Text('Türkçe')),
                const ButtonSegment(value: AppLanguage.en, label: Text('English')),
              ],
              selected: {state.language},
              showSelectedIcon: false,
              onSelectionChanged: (v) => state.setLanguage(v.first),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.autoUpdate,
              onChanged: state.setAutoUpdate,
              title: Text(L.t('Güncellemeleri otomatik denetle', 'Check for updates automatically')),
              subtitle: Text(
                Updater.supported
                    ? L.t('Uygulama açılırken yeni sürüm olup olmadığına bakılır.', 'Looks for a new version when the app starts.')
                    : Platform.isAndroid
                        ? L.t('Android sürümünde şimdilik güncelleme denetlenmez.', 'Updates aren’t checked on Android yet.')
                        : L.t('Geliştirme sürümünde güncelleme denetlenmez.', 'Updates aren’t checked in a development build.'),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.sendErrorReports,
              onChanged: state.setSendErrorReports,
              title: Text(L.t('Hata raporlarını gönder', 'Send error reports')),
              subtitle: Text(L.t(
                'Uygulamada beklenmeyen bir hata olursa, düzeltebilmemiz için kişisel bilgi içermeyen kısa bir rapor gönderilir. '
                    'Dosyalarınız ve adınız gönderilmez.',
                'If something unexpected goes wrong, a short report without personal information is sent so we can fix it. '
                    'Your files and name are never sent.',
              )),
            ),
          ],
        ),

        // ---- Yönetici izni ----
        if (state.service.isDesktop)
          _Section(
            title: L.t('Yönetici izni', 'Administrator rights'),
            children: [
              Row(
                children: [
                  Icon(
                    admin == true ? Icons.verified_user_outlined : Icons.shield_outlined,
                    color: admin == true ? AppColors.keepText : AppColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      admin == null
                          ? L.t('Kontrol ediliyor…', 'Checking…')
                          : admin
                              ? L.t('Uygulama yönetici izniyle çalışıyor. Sistem klasörleri de temizlenebilir.',
                                  'The app is running with administrator rights. System folders can be cleaned too.')
                              : L.t(
                                  'Uygulama normal izinle çalışıyor. Windows Update artıkları ve tüm kullanıcılara ait başlangıç programları için yönetici izni gerekir.',
                                  'The app is running with normal rights. Windows Update leftovers and startup apps for all users need administrator rights.',
                                ),
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ],
              ),
              if (admin == false) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => relaunchAsAdmin(context),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: Text(L.t('Yönetici olarak yeniden başlat', 'Restart as administrator')),
                ),
              ],
            ],
          ),

        // ---- Kopya bulucu ----
        _Section(
          title: L.t('Kopya dosya bulucu', 'Duplicate finder'),
          children: [
            Text(L.t('En küçük dosya boyutu', 'Smallest file size'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              L.t('Bundan küçük dosyalar karşılaştırılmaz. Büyük değer taramayı hızlandırır.',
                  'Smaller files aren’t compared. A larger value makes scanning faster.'),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: [for (final v in _sizes) ButtonSegment<int>(value: v, label: Text(formatBytes(v)))],
              selected: {selectedSize},
              showSelectedIcon: false,
              onSelectionChanged: (set) => state.setMinDuplicateSize(set.first),
            ),
            if (state.service.isDesktop) ...[
              const SizedBox(height: 22),
              Text(L.t('Hariç tutulan klasörler', 'Excluded folders'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                L.t('Bu klasörlerin içine hiç girilmez. Örneğin yedek veya proje klasörleri.',
                    'These folders are never searched, for example backups or project folders.'),
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final path in s.excluded)
                Row(
                  children: [
                    const Icon(Icons.folder_off_outlined, size: 18, color: AppColors.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(path, overflow: TextOverflow.ellipsis)),
                    IconButton(
                      tooltip: L.t('Listeden çıkar', 'Remove from list'),
                      onPressed: () => state.removeExcluded(path),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _addExcluded(state),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(L.t('Klasör ekle', 'Add folder')),
                ),
              ),
            ],
          ],
        ),

        // ---- Geçmiş ----
        _Section(
          title: L.t('Temizlik geçmişi', 'Cleanup history'),
          children: [
            Text(
              L.t('Şimdiye kadar toplam ${formatBytes(s.totalFreed)} alan açıldı.', '${formatBytes(s.totalFreed)} freed so far.'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (s.history.isEmpty)
              Text(L.t('Henüz temizlik yapılmadı.', 'No cleanups yet.'), style: const TextStyle(color: AppColors.muted))
            else ...[
              for (final h in s.history.take(20)) _HistoryRow(entry: h),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _clearHistory(context, state),
                  child: Text(L.t('Geçmişi temizle', 'Clear history')),
                ),
              ),
            ],
          ],
        ),

        if (state.store.path != null)
          Text(
            L.t('Ayar dosyası: ${state.store.path}', 'Settings file: ${state.store.path}'),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(formatTime(entry.date), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
          Expanded(child: Text(entry.title)),
          Text(formatBytes(entry.bytes), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
