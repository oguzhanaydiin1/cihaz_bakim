import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class LocationScreen extends StatelessWidget {
  const LocationScreen({super.key});

  static const maxShown = 300;

  Future<void> _remove(BuildContext context, AppState state) async {
    final count = state.selectedGps.length;
    final ok = await confirm(
      context,
      title: '$count fotoğraftan konum silinsin mi?',
      message: 'Fotoğrafların kendisine dokunulmaz; yalnızca içlerindeki konum kaydı silinir. '
          'Bu işlem geri alınamaz.',
      action: 'Konumu sil',
    );
    if (!ok || !context.mounted) return;
    final (cleaned, failed) = await state.removeSelectedLocations();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$cleaned fotoğraftan konum bilgisi silindi.${failed > 0 ? ' $failed fotoğraf işlenemedi.' : ''}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final photos = state.gpsPhotos;
    final busy = state.gpsBusy;

    final intro = Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!state.service.isSample) ...[
              FolderBar(
                path: state.gpsRoot,
                title: 'İncelenecek fotoğraf klasörünü seçin',
                enabled: !state.anyBusy,
                onChanged: (p) => state.findGpsPhotos(p),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Telefonla çekilen fotoğraflar genellikle çekildiği yerin konumunu içerir. '
              'Bu fotoğrafları paylaştığınızda konumunuz da paylaşılmış olur.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: state.anyBusy ? null : () => state.findGpsPhotos(),
              icon: const Icon(Icons.location_searching),
              label: Text(photos == null ? 'Konumlu Fotoğrafları Bul' : 'Yeniden Tara'),
            ),
          ],
        ),
      ),
    );

    final children = <Widget>[
      if (state.service.isSample) const SampleBanner(),
      intro,
    ];

    if (busy) {
      children.add(ProgressCard(
        title: photos == null ? 'Fotoğraflar inceleniyor…' : 'Konum bilgisi siliniyor…',
        progress: state.progress,
        onCancel: state.canCancel ? state.cancel : null,
      ));
    } else if (photos != null && photos.isEmpty) {
      children.add(const EmptyState(icon: Icons.location_off_outlined, text: 'Bu klasördeki fotoğraflarda konum bilgisi yok.'));
    } else if (photos != null) {
      final allSelected = photos.every((p) => p.selected);
      children.add(Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            CheckboxListTile(
              value: allSelected,
              onChanged: (v) => state.selectAllGps(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '${formatCount(photos.length)} fotoğrafta konum bilgisi var',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Divider(),
            for (final p in photos.take(maxShown)) _GpsRow(photo: p, onToggle: () => state.toggleGps(p)),
          ],
        ),
      ));
      if (photos.length > maxShown) {
        children.add(Text(
          'İlk $maxShown fotoğraf gösteriliyor; seçim tümüne uygulanır.',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ));
      }
    }

    final selected = state.selectedGps.length;
    return ModulePage(
      title: 'Konum Bilgisi Temizleyici',
      subtitle: 'Fotoğrafları paylaşmadan önce içlerindeki konum kaydını siler. Görüntü kalitesi değişmez.',
      bottom: photos == null || photos.isEmpty || busy
          ? null
          : ActionBar(
              label: 'Seçili fotoğraf',
              value: '$selected',
              buttonText: 'Konumu Sil',
              onPressed: selected == 0 || state.anyBusy ? null : () => _remove(context, state),
            ),
      children: children,
    );
  }
}

class _GpsRow extends StatelessWidget {
  const _GpsRow({required this.photo, required this.onToggle});

  final GpsPhoto photo;
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
            const Icon(Icons.location_on_outlined, size: 16, color: AppColors.warnText),
            const SizedBox(width: 4),
            Text(photo.coordinates, style: const TextStyle(fontSize: 13, color: AppColors.warnText, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
