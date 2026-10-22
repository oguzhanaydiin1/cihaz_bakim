import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/folder_picker.dart';

class DiskMapScreen extends StatelessWidget {
  const DiskMapScreen({super.key});

  /// En büyük N klasör ayrı gösterilir, kalanı "Diğer" kutusunda toplanır.
  static const maxCells = 9;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final usage = state.usage;
    final parent = state.usageParent;

    final header = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!state.service.isSample) ...[
          OutlinedButton.icon(
            onPressed: state.anyBusy ? null : () => _choose(state),
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: Text(L.t('Klasör seç', 'Choose folder')),
          ),
          if (parent != null)
            OutlinedButton.icon(
              onPressed: state.anyBusy ? null : () => state.loadUsage(parent),
              icon: const Icon(Icons.arrow_upward, size: 18),
              label: Text(L.t('Üst klasör', 'Up one level')),
            ),
        ],
        Text(state.usageRoot, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
      ],
    );

    Widget content;
    if (state.usageBusy) {
      content = ProgressCard(
        title: L.t('Klasör boyutları hesaplanıyor…', 'Calculating folder sizes…'),
        progress: state.progress,
        onCancel: state.canCancel ? state.cancel : null,
      );
    } else if (usage == null) {
      content = EmptyState(
        icon: Icons.dashboard_outlined,
        text: L.t('Hangi klasörlerin ne kadar yer kapladığını görmek için analizi başlatın.', 'Start the analysis to see how much space each folder takes.'),
        action: FilledButton(onPressed: state.anyBusy ? null : () => state.loadUsage(), child: Text(L.t('Analiz Et', 'Analyze'))),
      );
    } else if (usage.isEmpty) {
      content = EmptyState(icon: Icons.folder_off_outlined, text: L.t('Bu klasör boş ya da erişilemiyor.', 'This folder is empty or can’t be accessed.'));
    } else {
      final cells = _limit(usage);
      final total = cells.fold<int>(0, (s, u) => s + u.bytes);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: SizedBox(height: 400, child: _Treemap(items: cells, total: total, onOpen: state.loadUsage)),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < cells.length; i++) ...[
                  if (i > 0) const Divider(),
                  _UsageRow(item: cells[i], total: total, color: AppColors.map[i % AppColors.map.length], onOpen: state.loadUsage),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return ModulePage(
      title: L.t('Disk Haritası', 'Disk Map'),
      subtitle: L.t('Kutuların büyüklüğü kapladıkları alanla orantılıdır. Bir klasöre tıklayınca içine inilir.', 'Each box is sized by the space it takes. Click a folder to open it.'),
      children: [
        if (state.service.isSample) const SampleBanner(),
        header,
        content,
      ],
    );
  }

  Future<void> _choose(AppState state) async {
    final path = await pickFolder(L.t('İncelenecek klasörü veya sürücüyü seçin', 'Choose a folder or drive to analyze'), initialDirectory: state.usageRoot);
    if (path != null) await state.loadUsage(path);
  }

  List<FolderUsage> _limit(List<FolderUsage> usage) {
    if (usage.length <= maxCells) return usage;
    final top = usage.take(maxCells - 1).toList();
    final rest = usage.skip(maxCells - 1).fold<int>(0, (s, u) => s + u.bytes);
    return [...top, FolderUsage(name: 'Diğer', path: '', bytes: rest, isDir: false)];
  }
}

/// Basit iki satırlı ağaç haritası: büyükler üst satırda, küçükler alt satırda.
class _Treemap extends StatelessWidget {
  const _Treemap({required this.items, required this.total, required this.onOpen});

  final List<FolderUsage> items;
  final int total;
  final ValueChanged<String> onOpen;

  int _flex(int bytes) => math.max(1, (bytes / math.max(total, 1) * 1000).round());

  @override
  Widget build(BuildContext context) {
    final rows = <List<int>>[[], []];
    var acc = 0;
    for (var i = 0; i < items.length; i++) {
      rows[acc < total * 0.55 ? 0 : 1].add(i);
      acc += items[i].bytes;
    }
    final nonEmpty = rows.where((r) => r.isNotEmpty).toList();

    return Column(
      children: [
        for (var r = 0; r < nonEmpty.length; r++) ...[
          if (r > 0) const SizedBox(height: 4),
          Expanded(
            flex: _flex(nonEmpty[r].fold<int>(0, (s, i) => s + items[i].bytes)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var k = 0; k < nonEmpty[r].length; k++) ...[
                  if (k > 0) const SizedBox(width: 4),
                  Expanded(
                    flex: _flex(items[nonEmpty[r][k]].bytes),
                    child: _Cell(
                      item: items[nonEmpty[r][k]],
                      total: total,
                      color: AppColors.map[nonEmpty[r][k] % AppColors.map.length],
                      onOpen: onOpen,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.item, required this.total, required this.color, required this.onOpen});

  final FolderUsage item;
  final int total;
  final Color color;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final pct = (item.bytes / math.max(total, 1) * 100).round();
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.isDir ? () => onOpen(item.path) : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(folderLabel(item.name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(
                    L.t('${formatBytes(item.bytes)} · %$pct', '${formatBytes(item.bytes)} · $pct%'),
                    style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.item, required this.total, required this.color, required this.onOpen});

  final FolderUsage item;
  final int total;
  final Color color;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final ratio = item.bytes / math.max(total, 1);
    return InkWell(
      onTap: item.isDir ? () => onOpen(item.path) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(folderLabel(item.name), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: ratio, minHeight: 6, backgroundColor: AppColors.line, color: color),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 90,
              child: Text(formatBytes(item.bytes), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Icon(Icons.chevron_right, color: item.isDir ? AppColors.muted : Colors.transparent),
          ],
        ),
      ),
    );
  }
}
