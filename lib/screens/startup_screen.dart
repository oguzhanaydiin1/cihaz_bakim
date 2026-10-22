import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    // Ekran açılınca listeyi bir kez yükle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppScope.read(context);
      if (state.startup == null) state.loadStartup();
    });
  }

  Future<void> _toggle(AppState state, StartupItem item) async {
    final error = await state.toggleStartup(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? (item.enabled ? L.t('${item.name} açılışta çalışacak.', '${item.name} will run at startup.') : L.t('${item.name} artık açılışta çalışmayacak.', '${item.name} will no longer run at startup.'))),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.startup;

    Widget content;
    if (items == null || (state.startupBusy && items.isEmpty)) {
      content = BusyCard(text: L.t('Başlangıç programları okunuyor…', 'Reading startup apps…'));
    } else if (items.isEmpty) {
      content = EmptyState(icon: Icons.check_circle_outline, text: L.t('Açılışta çalışan program bulunamadı.', 'No apps run at startup.'));
    } else {
      content = Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(),
              _StartupRow(
                item: items[i],
                onToggle: () => _toggle(state, items[i]),
                onReveal: () {
                  final path = items[i].targetPath;
                  if (path != null) state.service.revealInExplorer(path);
                },
              ),
            ],
          ],
        ),
      );
    }

    final enabledCount = (items ?? []).where((s) => s.enabled).length;
    final machineItems = (items ?? []).any((s) => s.scope == StartupScope.machine);

    return ModulePage(
      title: L.t('Başlangıç Programları', 'Startup Apps'),
      subtitle: L.t(
        'Bilgisayar açılırken kendiliğinden başlayan programlar. Kapatmak programı silmez; Görev Yöneticisi’ndeki gibi yalnızca açılışta çalışmasını engeller ve her zaman geri açılabilir.',
        'Programs that start by themselves when your computer starts. Turning one off doesn’t remove it; like Task Manager, it only stops it from starting and can always be turned back on.',
      ),
      children: [
        if (state.admin == false && machineItems)
          AdminBanner(message: L.t('“Tüm kullanıcılar” etiketli programları değiştirmek için yönetici izni gerekir.', 'Changing apps marked “All users” requires administrator rights.')),
        if (items != null && items.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(
                  L.t('$enabledCount program açılışta çalışıyor · ${items.length - enabledCount} kapalı', '$enabledCount run at startup · ${items.length - enabledCount} off'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: state.startupBusy ? null : state.loadStartup,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(L.t('Yenile', 'Refresh')),
              ),
            ],
          ),
        content,
      ],
    );
  }
}

class _StartupRow extends StatelessWidget {
  const _StartupRow({required this.item, required this.onToggle, required this.onReveal});

  final StartupItem item;
  final VoidCallback onToggle;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: item.enabled ? AppColors.text : AppColors.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Tag(
                      item.scope == StartupScope.machine ? L.t('Tüm kullanıcılar', 'All users') : L.t('Bu kullanıcı', 'This user'),
                      background: const Color(0xFFF3F4F6),
                      foreground: const Color(0xFF374151),
                    ),
                    Tag(
                      item.fromFolder ? L.t('Başlangıç klasörü', 'Startup folder') : L.t('Kayıt defteri', 'Registry'),
                      background: const Color(0xFFF3F4F6),
                      foreground: const Color(0xFF374151),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (item.targetPath != null)
            IconButton(
              tooltip: L.t('Dosya konumunu aç', 'Open file location'),
              onPressed: onReveal,
              icon: const Icon(Icons.folder_open_outlined, size: 20),
            ),
          const SizedBox(width: 4),
          Switch(value: item.enabled, onChanged: (_) => onToggle()),
        ],
      ),
    );
  }
}
