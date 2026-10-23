import 'package:flutter/material.dart';

import '../core/i18n.dart';
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
      title: L.t('Temizlensin mi?', 'Clean up?'),
      message: L.t('$total silinecek. Kullanımda olan dosyalar atlanır.', '$total will be deleted. Files in use are skipped.'),
      action: L.t('Temizle', 'Clean'),
    );
    if (!ok) return;
    final result = await state.cleanSelectedJunk();
    if (!context.mounted) return;
    final skipped = result.skippedFiles > 0
        ? L.t(' ${formatCount(result.skippedFiles)} dosya kullanımda olduğu için atlandı.', ' ${formatCount(result.skippedFiles)} files were skipped because they’re in use.')
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L.t('${formatBytes(result.freedBytes)} temizlendi.$skipped', '${formatBytes(result.freedBytes)} cleaned.$skipped'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final junk = state.junk;

    Widget content;
    if (state.junkBusy) {
      content = ProgressCard(
        title: junk == null ? L.t('Gereksiz dosyalar taranıyor…', 'Scanning for junk files…') : L.t('Temizleniyor…', 'Cleaning…'),
        progress: state.progress,
        onCancel: state.canCancel ? state.cancel : null,
      );
    } else if (junk == null) {
      content = EmptyState(
        icon: Icons.delete_outline,
        text: L.t('Geçici dosyaları, tarayıcı önbelleklerini ve sistem artıklarını bulmak için tarama başlatın.', 'Start a scan to find temporary files, browser caches and system leftovers.'),
        action: FilledButton(onPressed: state.anyBusy ? null : state.scanJunk, child: Text(L.t('Taramayı Başlat', 'Start scan'))),
      );
    } else if (junk.isEmpty) {
      content = EmptyState(icon: Icons.check_circle_outline, text: L.t('Temizlenecek gereksiz dosya bulunamadı.', 'No junk files to clean.'));
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
      title: L.t('Gereksiz Dosyalar', 'Junk Files'),
      subtitle: !state.service.isDesktop
          ? L.t('Android, başka uygulamaların önbelleğini silmeye izin vermez. Burada eski ekran görüntüleri ve sohbet uygulamalarının medyası gibi gözden geçirebileceğiniz dosyalar listelenir. Silmeden önce Android onay ister.', 'Android doesn’t let apps clear other apps’ caches. Listed here are files worth reviewing, such as old screenshots and chat app media. Android asks for confirmation before deleting.')
          : L.t('Silmek istediğiniz kategorileri seçin. Yalnızca klasörlerin içindeki dosyalar silinir, klasörler yerinde kalır.', 'Choose the categories to delete. Only the files inside the folders are deleted; the folders stay.'),
      bottom: junk == null || junk.isEmpty || state.junkBusy
          ? null
          : ActionBar(
              label: L.t('Seçili toplam', 'Selected total'),
              value: formatBytes(state.selectedJunkBytes),
              buttonText: L.t('Seçilenleri Temizle', 'Clean selected'),
              onPressed: state.selectedJunkBytes == 0 || state.anyBusy ? null : () => _clean(context, state),
            ),
      children: [
        if (state.service.isSample) const SampleBanner(),
        if (needsAdmin && !state.junkBusy)
          AdminBanner(message: L.t('Bazı sistem klasörleri yalnızca yönetici izniyle tamamen temizlenebilir.', 'Some system folders can only be fully cleaned with administrator rights.')),
        content,
        if (junk != null && !state.junkBusy)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: state.anyBusy ? null : state.scanJunk,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(L.t('Yeniden Tara', 'Scan again')),
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
    final countText = c.fileCount > 0 ? L.t(' · ${formatCount(c.fileCount)} dosya', ' · ${formatCount(c.fileCount)} files') : '';
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
                c.sizeBytes == 0 ? L.t('Boş', 'Empty') : formatBytes(c.sizeBytes),
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
