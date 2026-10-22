import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/folder_picker.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _sizes = <(int, String)>[
    (1024, '1 KB'),
    (100 * 1024, '100 KB'),
    (1024 * 1024, '1 MB'),
    (10 * 1024 * 1024, '10 MB'),
  ];

  Future<void> _addExcluded(AppState state) async {
    final path = await pickFolder('Kopya bulucunun atlayacağı klasörü seçin');
    if (path != null) await state.addExcluded(path);
  }

  Future<void> _clearHistory(BuildContext context, AppState state) async {
    final ok = await confirm(
      context,
      title: 'Geçmiş silinsin mi?',
      message: 'Temizlik geçmişi listesi silinir. Toplam temizlenen alan bilgisi korunur.',
      action: 'Sil',
    );
    if (ok) await state.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    final selectedSize = _sizes.any((e) => e.$1 == s.minDuplicateSize) ? s.minDuplicateSize : _sizes[1].$1;

    return ModulePage(
      title: 'Ayarlar',
      subtitle: 'Tercihleriniz ve temizlik geçmişiniz bu bilgisayarda saklanır.',
      children: [
        if (state.service.isSample) const SampleBanner(),

        // ---- Yönetici izni ----
        if (!state.service.isSample)
          _Section(
            title: 'Yönetici izni',
            children: [
              Row(
                children: [
                  Icon(
                    state.admin == true ? Icons.verified_user_outlined : Icons.shield_outlined,
                    color: state.admin == true ? AppColors.keepText : AppColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state.admin == null
                          ? 'Kontrol ediliyor…'
                          : state.admin == true
                              ? 'Uygulama yönetici izniyle çalışıyor. Sistem klasörleri de temizlenebilir.'
                              : 'Uygulama normal izinle çalışıyor. Windows Update artıkları ve tüm kullanıcılara ait '
                                  'başlangıç programları için yönetici izni gerekir.',
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ],
              ),
              if (state.admin == false) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => relaunchAsAdmin(context),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: const Text('Yönetici olarak yeniden başlat'),
                ),
              ],
            ],
          ),

        // ---- Kopya bulucu ----
        _Section(
          title: 'Kopya dosya bulucu',
          children: [
            const Text('En küçük dosya boyutu', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              'Bundan küçük dosyalar karşılaştırılmaz. Büyük değer taramayı hızlandırır.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: [for (final (v, label) in _sizes) ButtonSegment<int>(value: v, label: Text(label))],
              selected: {selectedSize},
              showSelectedIcon: false,
              onSelectionChanged: (set) => state.setMinDuplicateSize(set.first),
            ),
            if (!state.service.isSample) ...[
              const SizedBox(height: 22),
              const Text('Hariç tutulan klasörler', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Bu klasörlerin içine hiç girilmez. Örneğin yedek veya proje klasörleri.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final path in s.excluded)
                Row(
                  children: [
                    const Icon(Icons.folder_off_outlined, size: 18, color: AppColors.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(path, overflow: TextOverflow.ellipsis)),
                    IconButton(
                      tooltip: 'Listeden çıkar',
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
                  label: const Text('Klasör ekle'),
                ),
              ),
            ],
          ],
        ),

        // ---- Geçmiş ----
        _Section(
          title: 'Temizlik geçmişi',
          children: [
            Text(
              'Şimdiye kadar toplam ${formatBytes(s.totalFreed)} alan açıldı.',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (s.history.isEmpty)
              const Text('Henüz temizlik yapılmadı.', style: TextStyle(color: AppColors.muted))
            else ...[
              for (final h in s.history.take(20)) _HistoryRow(entry: h),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: () => _clearHistory(context, state), child: const Text('Geçmişi temizle')),
              ),
            ],
          ],
        ),

        if (state.store.path != null)
          Text(
            'Ayar dosyası: ${state.store.path}',
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
