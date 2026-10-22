import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class JunkScreen extends StatelessWidget {
  const JunkScreen({super.key});

  Future<void> _clean(BuildContext context, AppState state) async {
    final total = formatBytes(state.selectedJunkBytes);
    final ok = await confirm(
      context,
      title: 'Temizlensin mi?',
      message: '$total silinecek. Kullanımda olan dosyalar atlanır.',
      action: 'Temizle',
    );
    if (!ok) return;
    final result = await state.cleanSelectedJunk();
    if (!context.mounted) return;
    final skipped = result.skippedFiles > 0
        ? ' ${formatCount(result.skippedFiles)} dosya kullanımda olduğu için atlandı.'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${formatBytes(result.freedBytes)} temizlendi.$skipped')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final junk = state.junk;

    Widget content;
    if (state.junkBusy) {
      content = ProgressCard(
        title: junk == null ? 'Gereksiz dosyalar taranıyor…' : 'Temizleniyor…',
        progress: state.progress,
        onCancel: state.canCancel ? state.cancel : null,
      );
    } else if (junk == null) {
      content = EmptyState(
        icon: Icons.delete_outline,
        text: 'Geçici dosyaları, tarayıcı önbelleklerini ve sistem artıklarını bulmak için tarama başlatın.',
        action: FilledButton(onPressed: state.anyBusy ? null : state.scanJunk, child: const Text('Taramayı Başlat')),
      );
    } else if (junk.isEmpty) {
      content = const EmptyState(icon: Icons.check_circle_outline, text: 'Temizlenecek gereksiz dosya bulunamadı.');
    } else {
      content = Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < junk.length; i++) ...[
              if (i > 0) const Divider(),
              _JunkRow(category: junk[i], onToggle: () => state.toggleJunk(junk[i])),
            ],
          ],
        ),
      );
    }

    final needsAdmin = state.admin == false && (junk ?? []).any((c) => c.requiresAdmin && c.sizeBytes > 0);

    return ModulePage(
      title: 'Gereksiz Dosyalar',
      subtitle: state.service.isSample
          ? 'Android, başka uygulamaların önbelleğinin silinmesine izin vermez. Burada yalnızca erişilebilen dosyalar listelenir.'
          : 'Silmek istediğiniz kategorileri seçin. Yalnızca klasörlerin içindeki dosyalar silinir, klasörler yerinde kalır.',
      bottom: junk == null || junk.isEmpty || state.junkBusy
          ? null
          : ActionBar(
              label: 'Seçili toplam',
              value: formatBytes(state.selectedJunkBytes),
              buttonText: 'Seçilenleri Temizle',
              onPressed: state.selectedJunkBytes == 0 || state.anyBusy ? null : () => _clean(context, state),
            ),
      children: [
        if (state.service.isSample) const SampleBanner(),
        if (needsAdmin && !state.junkBusy)
          const AdminBanner(message: 'Bazı sistem klasörleri yalnızca yönetici izniyle tamamen temizlenebilir.'),
        content,
        if (junk != null && !state.junkBusy)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: state.anyBusy ? null : state.scanJunk,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Yeniden Tara'),
            ),
          ),
      ],
    );
  }
}

class _JunkRow extends StatelessWidget {
  const _JunkRow({required this.category, required this.onToggle});

  final JunkCategory category;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = category;
    final warning = c.warning;
    final countText = c.fileCount > 0 ? ' · ${formatCount(c.fileCount)} dosya' : '';
    return InkWell(
      onTap: c.blocked ? null : onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Checkbox(value: c.selected, onChanged: c.blocked ? null : (_) => onToggle()),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('${c.description}$countText', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  if (warning != null) ...[const SizedBox(height: 6), Tag(warning)],
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 84,
              child: Text(
                c.sizeBytes == 0 ? 'Boş' : formatBytes(c.sizeBytes),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
