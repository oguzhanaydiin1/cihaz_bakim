import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.module});

  final ModuleInfo module;

  @override
  Widget build(BuildContext context) {
    return ModulePage(
      title: module.name,
      subtitle: L.t('${module.description} Sürüm ${module.version} ile gelecek.', '${module.description} Coming in version ${module.version}.'),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t('Planlanan özellikler', 'Planned features'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                for (final p in module.plan)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 7),
                          child: Icon(Icons.circle, size: 6, color: AppColors.muted),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(p, style: const TextStyle(fontSize: 15, height: 1.5))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
