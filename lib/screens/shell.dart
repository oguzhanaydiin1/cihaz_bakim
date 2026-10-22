import 'package:flutter/material.dart';

import '../core/modules.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'apps_screen.dart';
import 'coming_soon_screen.dart';
import 'disk_map_screen.dart';
import 'duplicates_screen.dart';
import 'health_screen.dart';
import 'junk_screen.dart';
import 'location_screen.dart';
import 'media_screen.dart';
import 'settings_screen.dart';
import 'smart_scan_screen.dart';
import 'startup_screen.dart';
import 'system_screen.dart';

/// Ana iskelet: geniş ekranda sol menü, dar ekranda (telefon) çekmece menü.
class Shell extends StatelessWidget {
  const Shell({super.key});

  Widget _screenFor(ModuleId id) {
    switch (id) {
      case ModuleId.smartScan:
        return const SmartScanScreen();
      case ModuleId.junk:
        return const JunkScreen();
      case ModuleId.duplicates:
        return const DuplicatesScreen();
      case ModuleId.diskMap:
        return const DiskMapScreen();
      case ModuleId.startup:
        return const StartupScreen();
      case ModuleId.settings:
        return const SettingsScreen();
      case ModuleId.apps:
        return const AppsScreen();
      case ModuleId.system:
        return const SystemScreen();
      case ModuleId.health:
        return const HealthScreen();
      case ModuleId.media:
        return const MediaScreen();
      case ModuleId.metadata:
        return const LocationScreen();
      default:
        return ComingSoonScreen(module: moduleById(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = modules.where((m) => m.isAvailableOn(currentPlatform)).toList();
    final body = _screenFor(state.current);

    if (isNarrow(context)) {
      return Scaffold(
        appBar: AppBar(
          title: Text(moduleById(state.current).name, style: const TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
        ),
        drawer: Drawer(
          backgroundColor: AppColors.nav,
          child: Sidebar(
            items: items,
            current: state.current,
            onSelect: (id) {
              Navigator.of(context).pop();
              state.open(id);
            },
          ),
        ),
        body: SafeArea(top: false, child: body),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: 250, child: Sidebar(items: items, current: state.current, onSelect: state.open)),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.items, required this.current, required this.onSelect});

  final List<ModuleInfo> items;
  final ModuleId current;
  final ValueChanged<ModuleId> onSelect;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      const Padding(
        padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(7)),
              child: Image(image: AssetImage('assets/icon/app_logo.png'), width: 28, height: 28),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Harrier Cleaner',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    ];

    String? lastGroup;
    for (final m in items) {
      if (m.group != lastGroup) {
        lastGroup = m.group;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
          child: Text(
            m.group.toUpperCase(),
            style: const TextStyle(color: AppColors.navLabel, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
        ));
      }
      children.add(_NavItem(module: m, active: m.id == current, onTap: () => onSelect(m.id)));
    }

    return Container(
      color: AppColors.nav,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 22, 14, 22), children: children),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.module, required this.active, required this.onTap});

  final ModuleInfo module;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : AppColors.navText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? AppColors.navItem : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: AppColors.navItem,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 42),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(module.icon, size: 18, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      module.name,
                      style: TextStyle(color: color, fontSize: 14, fontWeight: active ? FontWeight.w600 : FontWeight.w500),
                    ),
                  ),
                  if (!module.isReady)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF334155) : AppColors.navItem,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'v${module.version}',
                        style: const TextStyle(color: AppColors.navLabel, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
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
