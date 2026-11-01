import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_info.dart';
import '../core/format.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/updater.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/oa_labs_mark.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final privacy = L.isTr ? AppInfo.privacyTr : AppInfo.privacyEn;

    return ModulePage(
      title: L.t('Hakkında', 'About'),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Wrap(
              spacing: 24,
              runSpacing: 20,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: const Image(image: AssetImage('assets/icon/app_logo.png'), width: 96, height: 96),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(AppInfo.name, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        L.t('Sürüm ${AppInfo.version}', 'Version ${AppInfo.version}'),
                        style: const TextStyle(color: AppColors.muted, fontSize: 15),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        L.t(
                          'Bilgisayarını derli toplu ve hızlı tutar: gereksiz ve kopya dosyalar, disk haritası, '
                              'başlangıç programları, sistem bilgisi ve gizlilik araçları. Ücretsiz ve reklamsız.',
                          'Keeps your computer tidy and fast: junk and duplicate files, a disk map, startup apps, '
                              'system info and privacy tools. Free and ad-free.',
                        ),
                        style: const TextStyle(height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _UpdateCard(state: state),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    OALabsSeal(
                      size: 88,
                      color: AppColors.nav,
                      accent: const Color(0xFFC97A16),
                      text: L.t(
                        'OA LABS · ATÖLYE · 2026 · OA LABS · ATÖLYE · 2026 · ',
                        'OA LABS · WORKSHOP · 2026 · OA LABS · WORKSHOP · 2026 · ',
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        L.t('OA Labs atölyesinde özenle yapıldı.', 'Carefully made at the OA Labs workshop.'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Row(L.t('Geliştirici', 'Developer'), '${AppInfo.developer} · ${AppInfo.company}'),
                _Row(L.t('İletişim', 'Contact'), AppInfo.email),
                _Row(L.t('Web sitesi', 'Website'), 'oalabs.dev'),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: () => state.service.openUrl(privacy),
                      child: Text(L.t('Gizlilik politikası', 'Privacy policy')),
                    ),
                    OutlinedButton(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: AppInfo.name,
                        applicationVersion: AppInfo.version,
                        applicationLegalese: '© ${AppInfo.copyrightYear} ${AppInfo.developer}',
                      ),
                      child: Text(L.t('Açık kaynak lisansları', 'Open source licenses')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '© ${AppInfo.copyrightYear} ${AppInfo.developer} · ${AppInfo.company}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final info = state.update;
    final last = state.lastUpdateCheck;

    final (String title, String detail) = switch (state.updateStatus) {
      UpdateStatus.unsupported => Platform.isAndroid
          ? (
              L.t('Android beta sürümü', 'Android beta'),
              L.t('Android sürümünde yeni sürümler şimdilik oalabs.dev’den elle indirilir.', 'On Android, new versions are downloaded from oalabs.dev for now.'),
            )
          : (
              L.t('Geliştirme sürümü', 'Development build'),
              L.t('Güncellemeler, kurulum dosyasıyla yüklenen sürümde çalışır.', 'Updates work in the version installed from the setup file.'),
            ),
      UpdateStatus.checking => (L.t('Denetleniyor…', 'Checking…'), ''),
      UpdateStatus.latest => (
          L.t('Uygulama güncel', 'You’re up to date'),
          last == null ? '' : L.t('Son denetim: ${formatTime(last)}', 'Last checked: ${formatTime(last)}'),
        ),
      UpdateStatus.available => (
          L.t('Yeni sürüm: ${info?.version ?? ''}', 'New version: ${info?.version ?? ''}'),
          info?.notes ?? '',
        ),
      UpdateStatus.downloading => (
          L.t('İndiriliyor… %${(state.downloadProgress * 100).round()}', 'Downloading… ${(state.downloadProgress * 100).round()}%'),
          '',
        ),
      UpdateStatus.ready => (L.t('Kuruluyor…', 'Installing…'), L.t('Uygulama birazdan yeniden açılacak.', 'The app will reopen shortly.')),
      UpdateStatus.error => (L.t('Güncelleme başarısız', 'Update failed'), state.updateError ?? ''),
    };

    final busy = state.updateStatus == UpdateStatus.checking ||
        state.updateStatus == UpdateStatus.downloading ||
        state.updateStatus == UpdateStatus.ready;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.updateStatus == UpdateStatus.available ? Icons.system_update : Icons.verified_outlined,
                  color: state.updateStatus == UpdateStatus.available ? AppColors.accent : AppColors.keepText,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detail, style: const TextStyle(color: AppColors.muted, height: 1.5)),
            ],
            if (state.updateStatus == UpdateStatus.downloading) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: state.downloadProgress, minHeight: 8, backgroundColor: AppColors.line),
              ),
            ],
            if (state.updateStatus != UpdateStatus.unsupported) ...[
              const SizedBox(height: 16),
              if (state.updateStatus == UpdateStatus.available)
                FilledButton.icon(
                  onPressed: busy ? null : state.installUpdate,
                  icon: const Icon(Icons.download),
                  label: Text(L.t('Güncelle ve yeniden başlat', 'Update and restart')),
                )
              else
                OutlinedButton.icon(
                  onPressed: busy ? null : () => state.checkForUpdates(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(L.t('Güncellemeleri denetle', 'Check for updates')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(color: AppColors.muted))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
