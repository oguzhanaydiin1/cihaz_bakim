import 'package:flutter/material.dart';

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
      title: '${app.name} kaldırılsın mı?',
      message: 'Programın kendi kaldırıcısı açılacak. Onun adımlarını tamamlayın; '
          'Windows izin isteyebilir.',
      action: 'Kaldır',
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
      messenger.showSnackBar(const SnackBar(
        content: Text('Program hâlâ listede. Kaldırıcı penceresi açıksa bitirdikten sonra Yenile’ye basın.'),
      ));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text('${app.name} kaldırıldı.')));

    final leftover = outcome.leftoverFolder;
    if (leftover == null || !mounted) return;
    final clean = await confirm(
      context,
      title: 'Kalan klasör bulundu',
      message: 'Program kaldırıldı ama klasörü yerinde kalmış:\n\n$leftover\n\n'
          'Geri Dönüşüm Kutusu’na taşınsın mı? Gerekirse oradan geri alabilirsiniz.',
      action: 'Taşı',
    );
    if (!clean || !mounted) return;
    final moved = await state.recycleLeftover(leftover);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(moved
          ? 'Kalan klasör Geri Dönüşüm Kutusu’na taşındı.'
          : 'Klasör taşınamadı. Bazı klasörler için yönetici izni gerekir.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final apps = state.apps;

    Widget content;
    if (apps == null) {
      content = const BusyCard(text: 'Kurulu programlar okunuyor…');
    } else if (apps.isEmpty) {
      content = const EmptyState(icon: Icons.apps, text: 'Kurulu program bulunamadı.');
    } else {
      final visible = _visible(apps);
      content = visible.isEmpty
          ? const EmptyState(icon: Icons.search_off, text: 'Aramayla eşleşen program yok.')
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
      title: 'Uygulama Kaldırıcı',
      subtitle: 'Bilgisayarınızdaki programlar. Kaldırma, programın kendi kaldırıcısıyla yapılır; '
          'ardından kalan klasör varsa onu da temizlemeyi önerir.',
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
                  hintText: 'Program ara',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            SegmentedButton<_AppSort>(
              segments: const [
                ButtonSegment(value: _AppSort.size, label: Text('Boyut')),
                ButtonSegment(value: _AppSort.name, label: Text('Ad')),
                ButtonSegment(value: _AppSort.date, label: Text('En eski')),
              ],
              selected: {_sort},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _sort = s.first),
            ),
            OutlinedButton.icon(
              onPressed: state.appsBusy ? null : state.loadApps,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Yenile'),
            ),
          ],
        ),
        if (apps != null && apps.isNotEmpty)
          Text(
            '${apps.length} program${total > 0 ? ' · bildirilen toplam boyut ${formatBytes(total)}' : ''}',
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
      if (app.version.isNotEmpty) 'Sürüm ${app.version}',
      if (app.installDate != null) 'Kuruldu: ${formatTime(app.installDate!).split(' ').first}',
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
              : OutlinedButton(onPressed: enabled ? onUninstall : null, child: const Text('Kaldır')),
        ],
      ),
    );
  }
}
