import 'package:flutter/material.dart';

import '../core/i18n.dart';
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
      title: L.t('${selected.length} fotoğraf küçültülsün mü?', 'Compress ${selected.length} photos?'),
      message: L.t('Toplam ${formatBytes(total)}. ', 'Total ${formatBytes(total)}. ') +
          (o.backup && !state.service.isDesktop && !state.service.isSample
              ? L.t('Fotoğraflar galerideki yerinde küçültülecek. Orijinaller “Harrier Cleaner Yedek” albümüne kopyalanacak; yer, albümü silince açılır. Android değiştirme izni isteyecek.',
                  'Photos will be compressed where they are in your gallery. Originals will be copied to the “Harrier Cleaner Yedek” album; the space is freed when you delete it. Android will ask for permission.')
              : o.backup
              ? L.t('Orijinaller Geri Dönüşüm Kutusu’na taşınacak; yer, kutu boşaltılınca açılır.',
                  'The originals will be moved to the Recycle Bin; the space is freed when you empty it.')
              : L.t('Orijinaller kalıcı olarak değiştirilecek, geri alınamaz.', 'The originals will be replaced permanently. This can’t be undone.')),
      action: L.t('Küçült', 'Compress'),
    );
    if (!ok || !context.mounted) return;
    final r = await state.compressSelectedPhotos();
    if (r == null || !context.mounted) return;
    final parts = <String>[
      L.t('${r.compressed} fotoğraf küçültüldü, ${formatBytes(r.savedBytes)} kazanıldı.', '${r.compressed} photos compressed, ${formatBytes(r.savedBytes)} saved.'),
      if (r.skipped > 0) L.t('${r.skipped} fotoğraf zaten yeterince küçük olduğu için atlandı.', '${r.skipped} photos were already small enough and were skipped.'),
      if (r.failed > 0) L.t('${r.failed} fotoğraf işlenemedi.', '${r.failed} photos couldn’t be processed.'),
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
            if (state.service.isDesktop) ...[
              FolderBar(
                path: state.photosRoot,
                title: L.t('Fotoğrafların bulunduğu klasörü seçin', 'Choose the folder with your photos'),
                enabled: !state.anyBusy,
                onChanged: (p) => state.findPhotos(p),
              ),
              const SizedBox(height: 18),
            ],
            Text(L.t('Kalite', 'Quality'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 85, label: Text(L.t('Yüksek kalite', 'High quality'))),
                ButtonSegment(value: 75, label: Text(L.t('Dengeli', 'Balanced'))),
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
            Text(L.t('Boyut sınırı', 'Size limit'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(L.t('Orijinal', 'Original'))),
                ButtonSegment(value: 3840, label: Text(L.t('En fazla 4K', 'Up to 4K'))),
                ButtonSegment(value: 1920, label: Text(L.t('En fazla Full HD', 'Up to Full HD'))),
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
              title: Text(
                state.service.isDesktop || state.service.isSample
                    ? L.t('Orijinalleri Geri Dönüşüm Kutusu’na yedekle', 'Back up originals to the Recycle Bin')
                    : L.t('Orijinalleri “Harrier Cleaner Yedek” albümüne yedekle', 'Back up originals to the “Harrier Cleaner Yedek” album'),
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                state.service.isDesktop || state.service.isSample
                    ? L.t('Önerilir. Sonuçtan memnunsanız kutuyu boşaltınca yer açılır.', 'Recommended. If you’re happy with the result, empty the bin to free the space.')
                    : L.t('Önerilir. Fotoğraflar galerideki yerinde küçültülür; sonuçtan memnunsanız yedek albümünü silince yer açılır.',
                        'Recommended. Photos are compressed where they are in your gallery; if you’re happy, delete the backup album to free the space.'),
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: state.anyBusy ? null : () => state.findPhotos(),
              icon: const Icon(Icons.search),
              label: Text(photos == null ? L.t('Fotoğrafları Bul', 'Find photos') : L.t('Yeniden Ara', 'Search again')),
            ),
            const SizedBox(height: 10),
            Text(
              L.t('1 MB’tan büyük JPEG fotoğraflar listelenir. En az %10 küçülmeyecek fotoğraflara dokunulmaz. Çekim tarihi gibi bilgiler korunur.',
                  'JPEG photos larger than 1 MB are listed. Photos that wouldn’t shrink by at least 10% are left alone. Details like the date taken are kept.'),
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
        title: photos == null ? L.t('Fotoğraflar aranıyor…', 'Looking for photos…') : L.t('Fotoğraflar işleniyor…', 'Processing photos…'),
        progress: state.progress,
        onCancel: state.canCancel ? state.cancel : null,
      ));
    } else if (photos != null && photos.isEmpty) {
      children.add(EmptyState(icon: Icons.photo_outlined, text: L.t('Bu klasörde 1 MB’tan büyük JPEG fotoğraf bulunamadı.', 'No JPEG photos larger than 1 MB in this folder.')));
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
                '${L.t('${formatCount(photos.length)} fotoğraf', '${formatCount(photos.length)} photos')} · ${formatBytes(photos.fold<int>(0, (s, p) => s + p.sizeBytes))}',
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
          L.t('En büyük $maxShown fotoğraf gösteriliyor; seçim tümüne uygulanır.', 'Showing the $maxShown largest photos; your selection applies to all.'),
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ));
      }
    }

    final selected = state.selectedPhotos;
    return ModulePage(
      title: L.t('Medya Küçültücü', 'Photo Compressor'),
      subtitle: L.t('Büyük fotoğrafları gözle görülür kalite kaybı olmadan küçültür.', 'Shrinks large photos without visible loss of quality.'),
      bottom: photos == null || photos.isEmpty || busy
          ? null
          : ActionBar(
              label: L.t('${selected.length} fotoğraf seçili', '${selected.length} photos selected'),
              value: formatBytes(selected.fold<int>(0, (s, p) => s + p.sizeBytes)),
              buttonText: L.t('Küçült', 'Compress'),
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
