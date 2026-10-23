import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppScope.read(context);
      if (!state.permissionsLoaded) state.loadPermissions();
    });
  }

  static (String, IconData) _kindInfo(PermissionKind k) => switch (k) {
        PermissionKind.camera => (L.t('Kamera', 'Camera'), Icons.videocam_outlined),
        PermissionKind.microphone => (L.t('Mikrofon', 'Microphone'), Icons.mic_none),
        PermissionKind.location => (L.t('Konum', 'Location'), Icons.location_on_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final overview = state.permissionOverview;

    final children = <Widget>[
      if (state.service.isSample) const SampleBanner(),
    ];

    if (!state.permissionsLoaded) {
      children.add(BusyCard(text: L.t('İzinler okunuyor…', 'Reading permissions…')));
    } else if (overview == null) {
      children.add(EmptyState(
        icon: Icons.shield_outlined,
        text: L.t('İzin bilgileri okunamadı.', 'Permission information couldn’t be read.'),
      ));
    } else {
      for (final kind in PermissionKind.values) {
        children.add(_KindCard(
          kind: kind,
          info: _kindInfo(kind),
          enabled: overview.enabled[kind],
          uses: overview.uses.where((u) => u.kind == kind).toList(),
          onSettings: () => state.service.openPrivacySettings(kind),
        ));
      }
      final phone = !state.service.isDesktop && !state.service.isSample;
      children.add(Text(
        phone
            ? L.t(
                'Android, uygulamaların izinleri en son ne zaman kullandığını diğer uygulamalara göstermez; bu kayıt Ayarlar > Gizlilik > Gizlilik panosu’nda görülebilir. Bir uygulamanın iznini değiştirmek için üzerine dokunun.',
                'Android doesn’t show other apps when a permission was last used; you can see this under Settings > Privacy > Privacy dashboard. Tap an app to change its permissions.',
              )
            : L.t(
          'Windows, masaüstü programlarının izinlerini tek tek kapatmaya izin vermez; yalnızca hepsini birden '
              'kapatabilirsiniz. Mağaza uygulamalarının izinlerini ise tek tek yönetebilirsiniz. '
              'Değiştirmek için “Ayarları aç” düğmesini kullanın.',
          'Windows doesn’t let you turn off permissions for individual desktop programs, only for all of them at once. '
              'Store apps can be managed one by one. Use “Open settings” to make changes.',
        ),
        style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5),
      ));
      children.add(Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: state.permissionsBusy ? null : state.loadPermissions,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(L.t('Yenile', 'Refresh')),
        ),
      ));
    }

    return ModulePage(
      title: L.t('İzin Kontrolü', 'App Permissions'),
      subtitle: !state.service.isDesktop && !state.service.isSample
          ? L.t('Kamera, mikrofon ve konumunuza hangi uygulamaların izni olduğunu gösterir.',
              'Shows which apps are allowed to use your camera, microphone and location.')
          : L.t(
        'Kamera, mikrofon ve konumunuza hangi uygulamaların eriştiğini ve en son ne zaman kullandığını gösterir.',
        'Shows which apps have accessed your camera, microphone and location, and when they last did.',
      ),
      children: children,
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.kind,
    required this.info,
    required this.enabled,
    required this.uses,
    required this.onSettings,
  });

  final PermissionKind kind;
  final (String, IconData) info;
  final bool? enabled;
  final List<PermissionUse> uses;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final (title, icon) = info;
    final on = enabled;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 16, 14),
            child: Row(
              children: [
                Icon(icon, color: AppColors.text),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                if (on != null)
                  on
                      ? Tag(L.t('Açık', 'On'), background: AppColors.keepBg, foreground: AppColors.keepText)
                      : Tag(L.t('Kapalı', 'Off'), background: const Color(0xFFF3F4F6), foreground: const Color(0xFF374151)),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: onSettings,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(L.t('Ayarları aç', 'Open settings')),
                ),
              ],
            ),
          ),
          const Divider(),
          if (uses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                L.t('Bu izni kullanan uygulama kaydı yok.', 'No apps have used this permission.'),
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else
            for (var i = 0; i < uses.length; i++) ...[
              if (i > 0) const Divider(),
              _UseRow(use: uses[i]),
            ],
        ],
      ),
    );
  }
}

class _UseRow extends StatelessWidget {
  const _UseRow({required this.use});

  final PermissionUse use;

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context).service;
    final phone = !service.isDesktop && !service.isSample;
    final last = use.lastUsed;
    final when = use.inUse
        ? null
        : phone
            ? L.t('İzni var', 'Allowed')
            : last == null
                ? L.t('Hiç kullanmadı', 'Never used')
                : L.t('Son kullanım: ${formatTime(last)}', 'Last used: ${formatTime(last)}');
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(use.appName, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  use.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (use.inUse)
            Tag(L.t('Şu an kullanıyor', 'In use now'), background: const Color(0xFFFEE2E2), foreground: const Color(0xFFB91C1C))
          else if (when != null)
            Text(when, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          if (use.storeApp && !use.allowed) ...[
            const SizedBox(width: 10),
            Tag(L.t('Engelli', 'Blocked'), background: const Color(0xFFF3F4F6), foreground: const Color(0xFF374151)),
          ],
          if (phone) const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
    // Android: dokununca uygulamanın izin ayarları açılır.
    return phone ? InkWell(onTap: () => service.openUrl('package:${use.detail}'), child: row) : row;
  }
}
