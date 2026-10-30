import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/format.dart';
import '../core/modules.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/media_thumb.dart';
import '../widgets/folder_picker.dart';

class DuplicatesScreen extends StatelessWidget {
  const DuplicatesScreen({super.key});

  /// Çok sayıda grupta arayüz yavaşlamasın diye ilk N grup gösterilir.
  static const maxGroups = 100;

  Future<void> _addFolder(AppState state) async {
    final path = await pickFolder(L.t('Kopyaların aranacağı klasörü seçin', 'Choose a folder to search for duplicates'));
    if (path != null) await state.addRoot(path);
  }

  Future<void> _delete(BuildContext context, AppState state) async {
    final total = formatBytes(state.selectedDupeBytes);
    final ok = await confirm(
      context,
      title: L.t('Kopyalar silinsin mi?', 'Delete duplicates?'),
      message: L.t('$total tutarındaki kopya dosyalar ${state.service.deleteDestination.toLowerCase()}.', '$total of duplicate files ${state.service.deleteDestination.toLowerCase()}.'),
      action: L.t('Sil', 'Delete'),
    );
    if (!ok) return;
    final count = await state.deleteSelectedDuplicates();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.t('${formatCount(count)} dosya silindi.', '${formatCount(count)} files deleted.'))));
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
            Text(L.t('Taranacak klasörler', 'Folders to scan'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final root in state.knownRoots)
                  FilterChip(
                    label: Text(state.service.rootLabel(root)),
                    tooltip: state.service.rootLabel(root),
                    selected: state.dupeRoots.contains(root),
                    onSelected: state.dupesBusy ? null : (_) => state.toggleRoot(root),
                    onDeleted: state.isCustomRoot(root) && !state.dupesBusy ? () => state.removeRoot(root) : null,
                  ),
                if (state.service.isDesktop)
                  ActionChip(
                    avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
                    label: Text(L.t('Klasör ekle', 'Add folder')),
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
                  L.t('${formatBytes(state.settings.minDuplicateSize)} altındaki dosyalar atlanır', 'Files under ${formatBytes(state.settings.minDuplicateSize)} are skipped') +
                      (state.settings.excluded.isEmpty ? '' : L.t(' · ${state.settings.excluded.length} klasör hariç', ' · ${state.settings.excluded.length} folders excluded')),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                TextButton(onPressed: () => state.open(ModuleId.settings), child: Text(L.t('Değiştir', 'Change'))),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: state.anyBusy || state.dupeRoots.isEmpty ? null : state.scanDuplicates,
              icon: const Icon(Icons.search),
              label: Text(dupes == null ? L.t('Kopyaları Bul', 'Find duplicates') : L.t('Yeniden Tara', 'Scan again')),
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
        title: L.t('Kopya dosyalar aranıyor…', 'Looking for duplicates…'),
        progress: state.progress,
        onCancel: state.canCancel ? state.cancel : null,
      ));
    } else if (dupes != null && dupes.isEmpty) {
      children.add(EmptyState(icon: Icons.check_circle_outline, text: L.t('Seçili klasörlerde kopya dosya bulunamadı.', 'No duplicates found in the selected folders.')));
    } else if (dupes != null) {
      final shown = dupes.take(maxGroups).toList();
      children.add(Text(
        L.t('${formatCount(dupes.length)} grupta toplam ${formatBytes(dupes.fold<int>(0, (s, g) => s + g.wastedBytes))} kopya bulundu.',
            '${formatBytes(dupes.fold<int>(0, (s, g) => s + g.wastedBytes))} of duplicates found in ${formatCount(dupes.length)} groups.'),
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
          L.t('En çok yer kaplayan $maxGroups grup gösteriliyor.', 'Showing the $maxGroups largest groups.'),
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ));
      }
    }

    return ModulePage(
      title: L.t('Kopya Dosyalar', 'Duplicate Files'),
      subtitle: L.t(
        'İçeriği birebir aynı olan dosyalar gruplanır. Her gruptan en eski dosya korunur; hangisinin kalacağını değiştirebilirsiniz.',
        'Files with exactly the same content are grouped. The oldest file in each group is kept; you can choose a different one.',
      ),
      bottom: dupes == null || dupes.isEmpty || (state.dupesBusy && state.progress != null)
          ? null
          : ActionBar(
              label: state.service.deleteDestination,
              value: formatBytes(state.selectedDupeBytes),
              buttonText: L.t('Kopyaları Sil', 'Delete duplicates'),
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
                L.t('${group.files.length} kopya · her biri ${formatBytes(group.size)}', '${group.files.length} copies · ${formatBytes(group.size)} each'),
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
                  MediaThumb(path: f.path),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.path, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                        Text(L.t('Değiştirilme: ${formatTime(f.modified)}', 'Modified: ${formatTime(f.modified)}'), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  if (state.service.isDesktop)
                    IconButton(
                      tooltip: L.t('Klasörde göster', 'Show in folder'),
                      onPressed: () => state.service.revealInExplorer(f.path),
                      icon: const Icon(Icons.folder_open_outlined, size: 20),
                    ),
                  const SizedBox(width: 4),
                  if (f.keep)
                    Tag.keep(L.t('Korunacak', 'Keep'))
                  else
                    TextButton(onPressed: () => state.keepDuplicate(group, f), child: Text(L.t('Bunu koru', 'Keep this'))),
                ],
              ),
            ),
          ),
        const Divider(),
      ],
    );
  }
}
