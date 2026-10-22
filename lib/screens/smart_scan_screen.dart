import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/format.dart';
import '../core/modules.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class SmartScanScreen extends StatelessWidget {
  const SmartScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final storage = state.storage;
    final ratio = storage?.usedRatio ?? 0;
    final scanned = state.lastScan != null;
    final reclaim = state.reclaimableBytes;

    final String title;
    if (state.scanning) {
      title = L.t('Taranıyor…', 'Scanning…');
    } else if (!scanned) {
      title = L.t('Cihazınızı tarayın', 'Scan your device');
    } else if (reclaim > 0) {
      title = L.t('${formatBytes(reclaim)} alan açılabilir', '${formatBytes(reclaim)} can be freed');
    } else {
      title = L.t('Her şey temiz görünüyor', 'Everything looks clean');
    }

    final lastScan = state.lastScan;
    final step = state.scanning || state.scanStep.isNotEmpty
        ? state.scanStep
        : (lastScan != null ? L.t('Son tarama: ${formatTime(lastScan)}', 'Last scan: ${formatTime(lastScan)}') : L.t('Henüz tarama yapılmadı', 'No scan yet'));
    final progress = state.progress;
    final live = state.scanning && progress != null ? progressLine(progress) : '';

    return ModulePage(
      title: L.t('Akıllı Tarama', 'Smart Scan'),
      subtitle: L.t('Tüm modüller tek seferde çalışır ve size kısa bir özet sunar. Hiçbir şey onayınız olmadan silinmez.',
          'All modules run at once and give you a short summary. Nothing is deleted without your approval.'),
      children: [
        if (state.service.isSample) const SampleBanner(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Wrap(
              spacing: 36,
              runSpacing: 24,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StorageRing(ratio: ratio, label: storage?.label ?? L.t('depolama', 'storage'), known: storage != null),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 14),
                      if (state.scanning) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(value: state.scanStage, minHeight: 8, backgroundColor: AppColors.line),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(step, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
                      if (live.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(live, style: const TextStyle(color: AppColors.text, fontSize: 13)),
                      ],
                      if (state.scanning && progress != null && progress.current.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          progress.current,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (state.scanning)
                        OutlinedButton.icon(
                          onPressed: state.cancel,
                          icon: const Icon(Icons.close, size: 18),
                          label: Text(L.t('İptal', 'Cancel')),
                        )
                      else
                        FilledButton.icon(
                          onPressed: state.anyBusy ? null : state.smartScan,
                          icon: const Icon(Icons.manage_search),
                          label: Text(scanned ? L.t('Yeniden Tara', 'Scan again') : L.t('Akıllı Taramayı Başlat', 'Start Smart Scan')),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (scanned && !state.scanning) ...[
          Text(L.t('Tarama özeti', 'Scan summary'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          _Summary(state: state),
        ],
      ],
    );
  }
}

class _StorageRing extends StatelessWidget {
  const _StorageRing({required this.ratio, required this.label, required this.known});

  final double ratio;
  final String label;
  final bool known;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 170,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: known ? ratio : 0,
            strokeWidth: 16,
            backgroundColor: AppColors.line,
            strokeCap: StrokeCap.butt,
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    known ? '%${(ratio * 100).round()}' : '—',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                  ),
                  Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final junk = state.junk ?? [];
    final junkBytes = junk.where((c) => !c.blocked).fold<int>(0, (s, c) => s + c.sizeBytes);
    final dupes = state.dupes ?? [];
    final dupeFiles = dupes.fold<int>(0, (s, g) => s + g.files.length - 1);
    final dupeBytes = dupes.fold<int>(0, (s, g) => s + g.wastedBytes);
    final usage = state.usage ?? [];
    final biggest = usage.isNotEmpty ? usage.first : null;
    final startup = state.startup;

    final cards = [
      _SummaryData(L.t('Gereksiz dosyalar', 'Junk files'), formatBytes(junkBytes), ModuleId.junk),
      _SummaryData(L.t('Kopya dosyalar', 'Duplicate files'), L.t('${formatCount(dupeFiles)} dosya · ${formatBytes(dupeBytes)}', '${formatCount(dupeFiles)} files · ${formatBytes(dupeBytes)}'), ModuleId.duplicates),
      _SummaryData(
        L.t('En çok yer kaplayan', 'Takes the most space'),
        biggest != null ? '${folderLabel(biggest.name)} · ${formatBytes(biggest.bytes)}' : '—',
        ModuleId.diskMap,
      ),
      if (startup != null)
        _SummaryData(
          L.t('Başlangıç programları', 'Startup apps'),
          L.t('${startup.where((s) => s.enabled).length} açılışta çalışıyor', '${startup.where((s) => s.enabled).length} run at startup'),
          ModuleId.startup,
        ),
      _SummaryData(L.t('Toplam temizlenen', 'Total cleaned'), formatBytes(state.totalFreed), ModuleId.settings, action: L.t('Geçmişi gör →', 'See history →')),
    ];

    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final c in cards)
          SizedBox(
            width: 250,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => state.open(c.target),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label, style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        c.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.action,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryData {
  _SummaryData(this.label, this.value, this.target, {String? action}) : action = action ?? L.t('İncele →', 'Review →');
  final String label;
  final String value;
  final ModuleId target;
  final String action;
}
