import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

enum _AppSort { size, name, date }

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  final _search = TextEditingController();
  _AppSort _sort = _AppSort.size;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppScope.read(context);
      if (state.apps == null) state.loadApps();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<InstalledApp> _visible(List<InstalledApp> all) {
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? [...all]
        : all.where((a) => a.name.toLowerCase().contains(q) || a.publisher.toLowerCase().contains(q)).toList();
    switch (_sort) {
      case _AppSort.size:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      case _AppSort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _AppSort.date:
        list.sort((a, b) => (a.installDate ?? DateTime(1970)).compareTo(b.installDate ?? DateTime(1970)));
    }
    return list;
  }

  Future<void> _uninstall(AppState state, InstalledApp app) async {
    final ok = await confirm(
      context,
      title: L.t('${app.name} kaldırılsın mı?', 'Uninstall ${app.name}?'),
      message: state.service.isDesktop
          ? L.t(
              'Programın kendi kaldırıcısı açılacak. Onun adımlarını tamamlayın; Windows izin isteyebilir.',
              'The program’s own uninstaller will open. Follow its steps; Windows may ask for permission.',
            )
          : L.t('Android’in kaldırma onay penceresi açılacak.', 'Android’s uninstall confirmation will open.'),
      action: L.t('Kaldır', 'Uninstall'),
    );
    if (!ok || !mounted) return;
    final outcome = await state.uninstall(app);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final error = outcome.error;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (!outcome.removed) {
      messenger.showSnackBar(SnackBar(
        content: Text(L.t('Program hâlâ listede. Kaldırıcı penceresi açıksa bitirdikten sonra Yenile’ye basın.', 'The program is still listed. If the uninstaller is open, finish it and then press Refresh.')),
      ));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(L.t('${app.name} kaldırıldı.', '${app.name} was uninstalled.'))));

    final leftover = outcome.leftoverFolder;
    if (leftover == null || !mounted) return;
    final clean = await confirm(
      context,
      title: L.t('Kalan klasör bulundu', 'Leftover folder found'),
      message: L.t(
        'Program kaldırıldı ama klasörü yerinde kalmış:\n\n$leftover\n\nGeri Dönüşüm Kutusu’na taşınsın mı? Gerekirse oradan geri alabilirsiniz.',
        'The program was removed but its folder is still there:\n\n$leftover\n\nMove it to the Recycle Bin? You can restore it from there if needed.',
      ),
      action: L.t('Taşı', 'Move'),
    );
    if (!clean || !mounted) return;
    final moved = await state.recycleLeftover(leftover);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(moved
          ? L.t('Kalan klasör Geri Dönüşüm Kutusu’na taşındı.', 'The leftover folder was moved to the Recycle Bin.')
          : L.t('Klasör taşınamadı. Bazı klasörler için yönetici izni gerekir.', 'The folder couldn’t be moved. Some folders need administrator rights.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final apps = state.apps;

    Widget content;
    if (apps == null) {
      content = BusyCard(text: L.t('Kurulu programlar okunuyor…', 'Reading installed programs…'));
    } else if (apps.isEmpty) {
      content = EmptyState(icon: Icons.apps, text: L.t('Kurulu program bulunamadı.', 'No installed programs found.'));
    } else {
      final visible = _visible(apps);
      content = visible.isEmpty
          ? EmptyState(icon: Icons.search_off, text: L.t('Aramayla eşleşen program yok.', 'No programs match your search.'))
          : Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0) const Divider(),
                    _AppRow(
                      app: visible[i],
                      busy: state.uninstalling == visible[i].registryKey,
                      enabled: state.uninstalling == null,
                      onUninstall: () => _uninstall(state, visible[i]),
                    ),
                  ],
                ],
              ),
            );
    }

    final total = (apps ?? []).fold<int>(0, (s, a) => s + a.sizeBytes);

    return ModulePage(
      title: L.t('Uygulama Kaldırıcı', 'Uninstaller'),
      subtitle: state.service.isDesktop || state.service.isSample
          ? L.t(
              'Bilgisayarınızdaki programlar. Kaldırma, programın kendi kaldırıcısıyla yapılır; ardından kalan klasör varsa onu da temizlemeyi önerir.',
              'The programs on your computer. Each is removed with its own uninstaller; afterwards, any leftover folder can be cleaned up too.',
            )
          : L.t('Telefonunuza sonradan yüklediğiniz uygulamalar. Boyut, uygulama dosyasının boyutudur; verileri ve önbelleği dahil değildir.',
              'Apps you installed on your phone. The size is the app file’s size; data and cache aren’t included.'),
      children: [
        if (state.service.isSample) const SampleBanner(),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: L.t('Program ara', 'Search programs'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            SegmentedButton<_AppSort>(
              segments: [
                ButtonSegment(value: _AppSort.size, label: Text(L.t('Boyut', 'Size'))),
                ButtonSegment(value: _AppSort.name, label: Text(L.t('Ad', 'Name'))),
                ButtonSegment(value: _AppSort.date, label: Text(L.t('En eski', 'Oldest'))),
              ],
              selected: {_sort},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _sort = s.first),
            ),
            OutlinedButton.icon(
              onPressed: state.appsBusy ? null : state.loadApps,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(L.t('Yenile', 'Refresh')),
            ),
          ],
        ),
        if (apps != null && apps.isNotEmpty)
          Text(
            L.t('${apps.length} program', '${apps.length} programs') +
                (total > 0 ? L.t(' · bildirilen toplam boyut ${formatBytes(total)}', ' · reported total size ${formatBytes(total)}') : ''),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        content,
      ],
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.busy, required this.enabled, required this.onUninstall});

  final InstalledApp app;
  final bool busy;
  final bool enabled;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (app.publisher.isNotEmpty) app.publisher,
      if (app.version.isNotEmpty) L.t('Sürüm ${app.version}', 'Version ${app.version}'),
      if (app.installDate != null) L.t('Kuruldu: ${formatDate(app.installDate!)}', 'Installed: ${formatDate(app.installDate!)}'),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(details, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: Text(
              app.sizeBytes > 0 ? formatBytes(app.sizeBytes) : '—',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          busy
              ? const SizedBox(width: 92, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
              : OutlinedButton(onPressed: enabled ? onUninstall : null, child: Text(L.t('Kaldır', 'Uninstall'))),
        ],
      ),
    );
  }
}
