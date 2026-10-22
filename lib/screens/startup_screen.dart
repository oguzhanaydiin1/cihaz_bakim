import 'package:flutter/material.dart';

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
      content: Text(error ?? (item.enabled ? '${item.name} açılışta çalışacak.' : '${item.name} artık açılışta çalışmayacak.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.startup;

    Widget content;
    if (items == null || (state.startupBusy && items.isEmpty)) {
      content = const BusyCard(text: 'Başlangıç programları okunuyor…');
    } else if (items.isEmpty) {
      content = const EmptyState(icon: Icons.check_circle_outline, text: 'Açılışta çalışan program bulunamadı.');
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
      title: 'Başlangıç Programları',
      subtitle: 'Bilgisayar açılırken kendiliğinden başlayan programlar. Kapatmak programı silmez; '
          'Görev Yöneticisi’ndeki gibi yalnızca açılışta çalışmasını engeller ve her zaman geri açılabilir.',
      children: [
        if (state.admin == false && machineItems)
          const AdminBanner(message: '“Tüm kullanıcılar” etiketli programları değiştirmek için yönetici izni gerekir.'),
        if (items != null && items.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(
                  '$enabledCount program açılışta çalışıyor · ${items.length - enabledCount} kapalı',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: state.startupBusy ? null : state.loadStartup,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Yenile'),
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
                      item.scope == StartupScope.machine ? 'Tüm kullanıcılar' : 'Bu kullanıcı',
                      background: const Color(0xFFF3F4F6),
                      foreground: const Color(0xFF374151),
                    ),
                    Tag(
                      item.fromFolder ? 'Başlangıç klasörü' : 'Kayıt defteri',
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
              tooltip: 'Dosya konumunu aç',
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
