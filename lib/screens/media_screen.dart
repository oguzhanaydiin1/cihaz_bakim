import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  /// Çok uzun listelerde arayüz yavaşlamasın diye ilk N fotoğraf gösterilir.
  static const maxShown = 300;

  Future<void> _compress(BuildContext context, AppState state) async {
    final selected = state.selectedPhotos;
    final total = selected.fold<int>(0, (s, p) => s + p.sizeBytes);
    final o = state.compressOptions;
    final ok = await confirm(
      context,
      title: '${selected.length} fotoğraf küçültülsün mü?',
      message: 'Toplam ${formatBytes(total)}. '
          '${o.backup ? 'Orijinaller Geri Dönüşüm Kutusu’na taşınacak; yer, kutu boşaltılınca açılır.' : 'Orijinaller kalıcı olarak değiştirilecek, geri alınamaz.'}',
      action: 'Küçült',
    );
    if (!ok || !context.mounted) return;
    final r = await state.compressSelectedPhotos();
    if (r == null || !context.mounted) return;
    final parts = <String>[
      '${r.compressed} fotoğraf küçültüldü, ${formatBytes(r.savedBytes)} kazanıldı.',
      if (r.skipped > 0) '${r.skipped} fotoğraf zaten yeterince küçük olduğu için atlandı.',
      if (r.failed > 0) '${r.failed} fotoğraf işlenemedi.',
    ];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parts.join(' '))));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final photos = state.photos;
    final o = state.compressOptions;
    final busy = state.photosBusy;

    final options = Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!state.service.isSample) ...[
              FolderBar(
                path: state.photosRoot,
                title: 'Fotoğrafların bulunduğu klasörü seçin',
                enabled: !state.anyBusy,
                onChanged: (p) => state.findPhotos(p),
              ),
              const SizedBox(height: 18),
            ],
            const Text('Kalite', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 85, label: Text('Yüksek kalite')),
                ButtonSegment(value: 75, label: Text('Dengeli')),
              ],
              selected: {o.quality},
              showSelectedIcon: false,
              onSelectionChanged: busy
                  ? null
                  : (s) => state.setCompressOptions(
                        CompressOptions(quality: s.first, maxDimension: o.maxDimension, backup: o.backup),
                      ),
            ),
            const SizedBox(height: 16),
            const Text('Boyut sınırı', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Orijinal')),
                ButtonSegment(value: 3840, label: Text('En fazla 4K')),
                ButtonSegment(value: 1920, label: Text('En fazla Full HD')),
              ],
              selected: {o.maxDimension},
              showSelectedIcon: false,
              onSelectionChanged: busy
                  ? null
                  : (s) => state.setCompressOptions(
                        CompressOptions(quality: o.quality, maxDimension: s.first, backup: o.backup),
                      ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: o.backup,
              onChanged: busy
                  ? null
                  : (v) => state.setCompressOptions(
                        CompressOptions(quality: o.quality, maxDimension: o.maxDimension, backup: v),
                      ),
              title: const Text('Orijinalleri Geri Dönüşüm Kutusu’na yedekle', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Önerilir. Sonuçtan memnunsanız kutuyu boşaltınca yer açılır.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: state.anyBusy ? null : () => state.findPhotos(),
              icon: const Icon(Icons.search),
              label: Text(photos == null ? 'Fotoğrafları Bul' : 'Yeniden Ara'),
            ),
            const SizedBox(height: 10),
            const Text(
              '1 MB’tan büyük JPEG fotoğraflar listelenir. En az %10 küçülmeyecek fotoğraflara dokunulmaz. '
              'Çekim tarihi gibi bilgiler korunur.',
              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );

    final children = <Widget>[
      if (state.service.isSample) const SampleBanner(),
      options,
    ];

    if (busy) {
      children.add(ProgressCard(
        title: photos == null ? 'Fotoğraflar aranıyor…' : 'Fotoğraflar işleniyor…',
        progress: state.progress,
        onCancel: state.canCancel ? state.cancel : null,
      ));
    } else if (photos != null && photos.isEmpty) {
      children.add(const EmptyState(icon: Icons.photo_outlined, text: 'Bu klasörde 1 MB’tan büyük JPEG fotoğraf bulunamadı.'));
    } else if (photos != null) {
      final allSelected = photos.every((p) => p.selected);
      final shown = photos.take(maxShown).toList();
      children.add(Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            CheckboxListTile(
              value: allSelected,
              onChanged: (v) => state.selectAllPhotos(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '${formatCount(photos.length)} fotoğraf · ${formatBytes(photos.fold<int>(0, (s, p) => s + p.sizeBytes))}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Divider(),
            for (final p in shown) _PhotoRow(photo: p, onToggle: () => state.togglePhoto(p)),
          ],
        ),
      ));
      if (photos.length > maxShown) {
        children.add(Text(
          'En büyük $maxShown fotoğraf gösteriliyor; seçim tümüne uygulanır.',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ));
      }
    }

    final selected = state.selectedPhotos;
    return ModulePage(
      title: 'Medya Küçültücü',
      subtitle: 'Büyük fotoğrafları gözle görülür kalite kaybı olmadan küçültür.',
      bottom: photos == null || photos.isEmpty || busy
          ? null
          : ActionBar(
              label: '${selected.length} fotoğraf seçili',
              value: formatBytes(selected.fold<int>(0, (s, p) => s + p.sizeBytes)),
              buttonText: 'Küçült',
              onPressed: selected.isEmpty || state.anyBusy ? null : () => _compress(context, state),
            ),
      children: children,
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.photo, required this.onToggle});

  final PhotoFile photo;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Checkbox(value: photo.selected, onChanged: (_) => onToggle()),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(baseName(photo.path), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(photo.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(formatBytes(photo.sizeBytes), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
