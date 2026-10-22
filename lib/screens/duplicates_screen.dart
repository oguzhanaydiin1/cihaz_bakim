import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/modules.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/folder_picker.dart';

class DuplicatesScreen extends StatelessWidget {
  const DuplicatesScreen({super.key});

  /// Çok sayıda grupta arayüz yavaşlamasın diye ilk N grup gösterilir.
  static const maxGroups = 100;

  Future<void> _addFolder(AppState state) async {
    final path = await pickFolder('Kopyaların aranacağı klasörü seçin');
    if (path != null) await state.addRoot(path);
  }

  Future<void> _delete(BuildContext context, AppState state) async {
    final total = formatBytes(state.selectedDupeBytes);
    final ok = await confirm(
      context,
      title: 'Kopyalar silinsin mi?',
      message: '$total tutarındaki kopya dosyalar ${state.service.deleteDestination.toLowerCase()}.',
      action: 'Sil',
    );
    if (!ok) return;
    final count = await state.deleteSelectedDuplicates();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${formatCount(count)} dosya silindi.')));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final dupes = state.dupes;

    final folders = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Taranacak klasörler', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final root in state.knownRoots)
                  FilterChip(
                    label: Text(baseName(root)),
                    tooltip: root,
                    selected: state.dupeRoots.contains(root),
                    onSelected: state.dupesBusy ? null : (_) => state.toggleRoot(root),
                    onDeleted: state.isCustomRoot(root) && !state.dupesBusy ? () => state.removeRoot(root) : null,
                  ),
                if (!state.service.isSample)
                  ActionChip(
                    avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
                    label: const Text('Klasör ekle'),
                    onPressed: state.dupesBusy ? null : () => _addFolder(state),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  '${formatBytes(state.settings.minDuplicateSize)} altındaki dosyalar atlanır'
                  '${state.settings.excluded.isEmpty ? '' : ' · ${state.settings.excluded.length} klasör hariç'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                TextButton(onPressed: () => state.open(ModuleId.settings), child: const Text('Değiştir')),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: state.anyBusy || state.dupeRoots.isEmpty ? null : state.scanDuplicates,
              icon: const Icon(Icons.search),
              label: Text(dupes == null ? 'Kopyaları Bul' : 'Yeniden Tara'),
            ),
          ],
        ),
      ),
    );

    final children = <Widget>[
      if (state.service.isSample) const SampleBanner(),
      folders,
    ];

    if (state.dupesBusy && state.progress != null) {
      children.add(ProgressCard(
        title: 'Kopya dosyalar aranıyor…',
        progress: state.progress,
        onCancel: state.canCancel ? state.cancel : null,
      ));
    } else if (dupes != null && dupes.isEmpty) {
      children.add(const EmptyState(icon: Icons.check_circle_outline, text: 'Seçili klasörlerde kopya dosya bulunamadı.'));
    } else if (dupes != null) {
      final shown = dupes.take(maxGroups).toList();
      children.add(Text(
        '${formatCount(dupes.length)} grupta toplam ${formatBytes(dupes.fold<int>(0, (s, g) => s + g.wastedBytes))} kopya bulundu.',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ));
      children.add(Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final g in shown) _GroupView(group: g, state: state),
          ],
        ),
      ));
      if (dupes.length > maxGroups) {
        children.add(Text(
          'En çok yer kaplayan $maxGroups grup gösteriliyor.',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ));
      }
    }

    return ModulePage(
      title: 'Kopya Dosyalar',
      subtitle: 'İçeriği birebir aynı olan dosyalar gruplanır. Her gruptan en eski dosya korunur; '
          'hangisinin kalacağını değiştirebilirsiniz.',
      bottom: dupes == null || dupes.isEmpty || (state.dupesBusy && state.progress != null)
          ? null
          : ActionBar(
              label: state.service.deleteDestination,
              value: formatBytes(state.selectedDupeBytes),
              buttonText: 'Kopyaları Sil',
              busy: state.dupesBusy,
              onPressed: state.selectedDupeBytes == 0 || state.anyBusy ? null : () => _delete(context, state),
            ),
      children: children,
    );
  }
}

class _GroupView extends StatelessWidget {
  const _GroupView({required this.group, required this.state});

  final DuplicateGroup group;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.groupHead,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${group.files.length} kopya · her biri ${formatBytes(group.size)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        for (final f in group.files)
          InkWell(
            onTap: f.keep ? null : () => state.toggleDuplicate(f),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Checkbox(value: f.selected, onChanged: f.keep ? null : (_) => state.toggleDuplicate(f)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.path, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                        Text('Değiştirilme: ${formatTime(f.modified)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  if (!state.service.isSample)
                    IconButton(
                      tooltip: 'Klasörde göster',
                      onPressed: () => state.service.revealInExplorer(f.path),
                      icon: const Icon(Icons.folder_open_outlined, size: 20),
                    ),
                  const SizedBox(width: 4),
                  if (f.keep)
                    const Tag.keep('Korunacak')
                  else
                    TextButton(onPressed: () => state.keepDuplicate(group, f), child: const Text('Bunu koru')),
                ],
              ),
            ),
          ),
        const Divider(),
      ],
    );
  }
}
