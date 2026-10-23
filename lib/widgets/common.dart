import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'folder_picker.dart';

bool isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 860;

/// Her modül ekranının ortak iskeleti: başlık, kaydırılabilir içerik, alt eylem çubuğu.
class ModulePage extends StatelessWidget {
  const ModulePage({super.key, required this.title, this.subtitle, required this.children, this.bottom});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final narrow = isNarrow(context);
    final pad = narrow ? 16.0 : 40.0;
    final sub = subtitle;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, narrow ? 16 : 36, pad, 24),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!narrow)
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                          letterSpacing: -0.5,
                        ),
                      ),
                    if (sub != null)
                      Padding(
                        padding: EdgeInsets.only(top: narrow ? 0 : 6),
                        child: Text(sub, style: const TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5)),
                      ),
                    const SizedBox(height: 22),
                    const MediaAccessBanner(),
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: 18),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (bottom != null)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, narrow ? 16 : 24),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: bottom),
            ),
          ),
      ],
    );
  }
}

/// Koyu alt çubuk: solda toplam, sağda ana eylem.
class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.label,
    required this.value,
    required this.buttonText,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final String value;
  final String buttonText;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(color: AppColors.nav, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.navText, fontSize: 13)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: busy ? null : onPressed,
            child: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(buttonText),
          ),
        ],
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.background = AppColors.warnBg, this.foreground = AppColors.warnText});

  const Tag.keep(this.text, {super.key})
      : background = AppColors.keepBg,
        foreground = AppColors.keepText;

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final a = action;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15, height: 1.5)),
            if (a != null) ...[const SizedBox(height: 18), a],
          ],
        ),
      ),
    );
  }
}

class BusyCard extends StatelessWidget {
  const BusyCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// "1.234 dosya · 2,1 GB" gibi canlı ilerleme satırı.
String progressLine(ScanProgress p) {
  final parts = <String>[];
  if (p.phase.isNotEmpty) parts.add(L.phase(p.phase));
  if (p.total > 0) {
    parts.add(L.t('${formatCount(p.files)} / ${formatCount(p.total)} dosya', '${formatCount(p.files)} / ${formatCount(p.total)} files'));
  } else if (p.files > 0) {
    parts.add(L.t('${formatCount(p.files)} dosya', '${formatCount(p.files)} files'));
  }
  if (p.bytes > 0) parts.add(formatBytes(p.bytes));
  return parts.join(' · ');
}

/// Süren bir taramayı canlı sayaç ve iptal butonuyla gösterir.
class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key, required this.title, this.progress, this.onCancel});

  final String title;
  final ScanProgress? progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final p = progress ?? const ScanProgress();
    final line = progressLine(p);
    final cancel = onCancel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: p.total > 0 ? (p.files / p.total).clamp(0.0, 1.0) : null,
                minHeight: 8,
                backgroundColor: AppColors.line,
              ),
            ),
            const SizedBox(height: 12),
            Text(line.isEmpty ? L.t('Başlatılıyor…', 'Starting…') : line, style: const TextStyle(fontSize: 14, color: AppColors.text)),
            if (p.current.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                p.current,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
            if (cancel != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(onPressed: cancel, icon: const Icon(Icons.close, size: 18), label: Text(L.t('İptal', 'Cancel'))),
            ],
          ],
        ),
      ),
    );
  }
}

/// Yönetici izni gereken durumlarda gösterilen şerit.
class AdminBanner extends StatelessWidget {
  const AdminBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(12)),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 20, color: AppColors.accent),
                const SizedBox(width: 10),
                Flexible(child: Text(message, style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF1E3A8A)))),
              ],
            ),
          ),
          TextButton(onPressed: () => relaunchAsAdmin(context), child: Text(L.t('Yönetici olarak yeniden başlat', 'Restart as administrator'))),
        ],
      ),
    );
  }
}

Future<void> relaunchAsAdmin(BuildContext context) async {
  final ok = await confirm(
    context,
    title: L.t('Yönetici olarak yeniden başlatılsın mı?', 'Restart as administrator?'),
    message: L.t('Uygulama kapanıp yönetici izniyle yeniden açılacak. Windows izin isteyecek; onay vermeniz gerekir.',
        'The app will close and reopen with administrator rights. Windows will ask for permission; you’ll need to approve it.'),
    action: L.t('Yeniden başlat', 'Restart'),
  );
  if (!ok || !context.mounted) return;
  final started = await AppScope.read(context).relaunchAsAdmin();
  if (!started && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.t('Yönetici izni verilmedi.', 'Administrator rights weren’t granted.'))));
  }
}

/// Gerçek tarama yapılamayan platformlarda gösterilen bilgi şeridi.
class SampleBanner extends StatelessWidget {
  const SampleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: AppColors.warnText),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              L.t('Bu platformda örnek veriler gösteriliyor. Gerçek tarama şu an yalnızca Windows sürümünde çalışıyor.',
                  'Sample data is shown on this platform. Real scanning currently works only in the Windows version.'),
              style: TextStyle(color: AppColors.warnText, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, {required String title, required String message, required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t('Vazgeç', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

/// Seçili klasörü gösterir ve "Klasör seç" butonu sunar.
class FolderBar extends StatelessWidget {
  const FolderBar({super.key, required this.path, required this.onChanged, this.enabled = true, this.title});

  final String path;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: enabled
              ? () async {
                  final p = await pickFolder(title ?? L.t('Klasör seçin', 'Choose a folder'), initialDirectory: path);
                  if (p != null) onChanged(p);
                }
              : null,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: Text(L.t('Klasör seç', 'Choose folder')),
        ),
        Text(path, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
      ],
    );
  }
}

/// Android: fotoğraf ve videolara erişim izni yoksa (ya da yalnızca bazı fotoğraflara izin
/// verildiyse) medya kullanan ekranların üstünde açıklama ve "İzin ver" düğmesi gösterir.
class MediaAccessBanner extends StatelessWidget {
  const MediaAccessBanner({super.key});

  static const _mediaModules = {
    ModuleId.smartScan,
    ModuleId.junk,
    ModuleId.duplicates,
    ModuleId.diskMap,
    ModuleId.media,
    ModuleId.metadata,
  };

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    final state = scope?.notifier;
    final access = state?.mediaAccess;
    if (state == null || access == null || !state.service.needsMediaPermission || !_mediaModules.contains(state.current)) {
      return const SizedBox.shrink();
    }
    final String? message;
    if (!access.granted) {
      message = L.t(
        'Taramak için fotoğraf, video ve müzik dosyalarınıza erişim izni gerekiyor. Dosyalarınız telefonunuzdan çıkmaz.',
        'Scanning needs access to your photos, videos and music. Your files never leave your phone.',
      );
    } else if (access.partial) {
      message = L.t(
        'Yalnızca seçtiğiniz fotoğraflara izin verdiniz; tarama sonuçları eksik olabilir.',
        'You allowed access to selected photos only, so results may be incomplete.',
      );
    } else if (state.current == ModuleId.metadata && !access.location) {
      message = L.t(
        'Fotoğraflardaki konum bilgisini görebilmek için “fotoğraflardaki konumlara erişim” izni gerekiyor.',
        'Seeing location data in photos needs the “access your media location” permission.',
      );
    } else {
      message = null;
    }
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(12)),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.photo_library_outlined, size: 20, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Flexible(child: Text(message, style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF1E3A8A)))),
                ],
              ),
            ),
            FilledButton(
              onPressed: state.requestMediaAccess,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: Text(access.granted ? L.t('İzni değiştir', 'Change access') : L.t('İzin ver', 'Allow access')),
            ),
          ],
        ),
      ),
    );
  }
}

