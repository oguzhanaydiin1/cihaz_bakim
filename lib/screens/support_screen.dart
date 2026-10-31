import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_info.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/error_reporter.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/oa_labs_mark.dart';

/// OA Radyo'daki "Destek" bölümünün karşılığı: iletişim bilgileri, sorun bildirme ve SSS.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  String _diagnostics() => [
        '${AppInfo.name} ${AppInfo.version}',
        'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'Lang: ${L.code}',
      ].join('\n');

  /// Sürüm ve sistem bilgisiyle hazırlanmış bir e-posta taslağı açar.
  void _reportProblem(AppState state) {
    final subject = L.t('${AppInfo.name} – Sorun bildirimi', '${AppInfo.name} – Problem report');
    final body = L.t(
      'Merhaba,\n\nYaşadığım sorun:\n\n\nSorun nasıl oluştu (adım adım):\n\n\n----\n${_diagnostics()}',
      'Hi,\n\nThe problem I ran into:\n\n\nHow it happened (step by step):\n\n\n----\n${_diagnostics()}',
    );
    final uri = Uri(scheme: 'mailto', path: AppInfo.email, query: _query({'subject': subject, 'body': body}));
    state.service.openUrl(uri.toString());
  }

  /// mailto için boşlukları "+" değil "%20" olarak kodlar (Outlook ve Gmail doğru gösterir).
  static String _query(Map<String, String> params) =>
      params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

  Future<void> _copyLog(BuildContext context) async {
    final log = ErrorReporter.recentLog();
    await Clipboard.setData(ClipboardData(text: '${_diagnostics()}\n\n${log.isEmpty ? '-' : log}'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(L.t(
        'Hata kaydı panoya kopyalandı. E-postana yapıştırabilirsin.',
        'Error log copied. You can paste it into your email.',
      )),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final privacy = L.isTr ? AppInfo.privacyTr : AppInfo.privacyEn;

    return ModulePage(
      title: L.t('İletişim ve Destek', 'Help & Contact'),
      subtitle: L.t(
        'Bir sorun mu yaşadın, bir önerin mi var? Yaz, okuyup yanıtlıyoruz.',
        'Ran into a problem or have an idea? Write to us, we read and reply.',
      ),
      children: [
        // ---- Geliştirici ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.nav, borderRadius: BorderRadius.circular(14)),
                      child: const OALabsMark(size: 34),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(AppInfo.developer, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          Text(
                            L.t('Yazılım Geliştirici · ${AppInfo.company}', 'Software Developer · ${AppInfo.company}'),
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _LinkRow(
                  icon: Icons.mail_outline,
                  label: L.t('E-posta', 'Email'),
                  value: AppInfo.email,
                  onTap: () => state.service.openUrl('mailto:${AppInfo.email}'),
                ),
                _LinkRow(
                  icon: Icons.language,
                  label: L.t('Web sitesi', 'Website'),
                  value: 'oalabs.dev',
                  onTap: () => state.service.openUrl(L.isTr ? AppInfo.website : '${AppInfo.website}en/'),
                ),
                _LinkRow(
                  icon: Icons.privacy_tip_outlined,
                  label: L.t('Gizlilik politikası', 'Privacy policy'),
                  value: L.t('Verilerin nasıl korunur?', 'How your data is protected'),
                  onTap: () => state.service.openUrl(privacy),
                ),
              ],
            ),
          ),
        ),

        // ---- Sorun bildir ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t('Sorun bildir', 'Report a problem'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  L.t(
                    'E-posta programın, uygulama sürümü ve cihaz bilgisiyle doldurulmuş bir taslakla açılır. '
                        'Hata kaydını da kopyalayıp e-postana ekleyebilirsin; sorunu bulmamızı çok kolaylaştırır.',
                    'Your email app opens with a draft that already includes the app version and device details. '
                        'You can also copy the error log into your email; it makes finding the problem much easier.',
                  ),
                  style: const TextStyle(color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _reportProblem(state),
                      icon: const Icon(Icons.edit_note),
                      label: Text(L.t('E-posta yaz', 'Write an email')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copyLog(context),
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(L.t('Hata kaydını kopyala', 'Copy error log')),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  ErrorReporter.recent.isEmpty
                      ? L.t('Bu oturumda hata kaydedilmedi.', 'No errors recorded in this session.')
                      : L.t('Bu oturumda ${ErrorReporter.recent.length} hata kaydedildi.',
                          '${ErrorReporter.recent.length} errors recorded in this session.'),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),

        // ---- Sık sorulan sorular ----
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                child: Text(L.t('Sık sorulan sorular', 'FAQ'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              if (!Platform.isAndroid)
              _Faq(
                L.t('Windows “Bilgisayarınız korundu” uyarısı veriyor.', 'Windows says “Windows protected your PC”.'),
                L.t(
                  'Uygulama henüz dijital olarak imzalanmadığı için Windows ilk açılışta bu uyarıyı gösterebilir. '
                      '“Ek bilgi”ye, ardından “Yine de çalıştır”a basman yeterli.',
                  'The app isn’t digitally signed yet, so Windows may show this the first time. '
                      'Choose “More info”, then “Run anyway”.',
                ),
              ),
              if (Platform.isAndroid) ...[
                _Faq(
                  L.t('Neden fotoğraf ve videolarıma erişim istiyor?', 'Why does it ask for access to my photos and videos?'),
                  L.t(
                    'Android, uygulamaların başka uygulamaların dosyalarına yalnızca fotoğraf, video ve müzik kütüphanesi üzerinden erişmesine izin verir. '
                        'Gereksiz dosyalar, kopyalar, disk haritası ve fotoğraf araçları bu kütüphaneyi tarar. Dosyaların hiçbir yere gönderilmez.',
                    'Android only lets apps reach other apps’ files through the photo, video and music library. '
                        'Junk files, duplicates, the disk map and the photo tools scan this library. Your files are never sent anywhere.',
                  ),
                ),
                _Faq(
                  L.t('Sildiğim dosyalar nereye gidiyor?', 'Where do deleted files go?'),
                  L.t(
                    'Kopyalar telefonun çöp kutusuna taşınır; 30 gün içinde geri alabilirsin. Küçültülen fotoğraflar galerideki yerinde kalır; '
                        'orijinalleri “Harrier Cleaner Yedek” albümüne kopyalanır. Gereksiz dosyalar kalıcı silinir. Her durumda Android önce onay ister.',
                    'Duplicates go to your phone’s trash, where you can restore them for 30 days. Compressed photos stay where they are in your gallery; '
                        'their originals are copied to the “Harrier Cleaner Yedek” album. Junk files are deleted permanently. Android always asks you first.',
                  ),
                ),
              ] else
              _Faq(
                L.t('Sildiğim dosyalar nereye gidiyor?', 'Where do deleted files go?'),
                L.t(
                  'Kopya dosyalar ve küçültülen fotoğrafların orijinalleri Geri Dönüşüm Kutusu’na taşınır; '
                      'oradan geri alabilirsin. Geçici dosyalar ve önbellekler doğrudan silinir, çünkü programlar '
                      'onları gerektiğinde yeniden oluşturur.',
                  'Duplicate files and the originals of compressed photos go to the Recycle Bin, so you can restore them. '
                      'Temporary files and caches are deleted directly, because programs recreate them when needed.',
                ),
              ),
              if (!Platform.isAndroid)
              _Faq(
                L.t('Neden yönetici izni istiyor?', 'Why does it ask for administrator rights?'),
                L.t(
                  'Windows Update artıkları gibi bazı sistem klasörlerine ve tüm kullanıcılara ait başlangıç '
                      'programlarına yalnızca yönetici erişebilir. Bunlar dışında uygulama normal izinle çalışır.',
                  'Some system folders, like Windows Update leftovers, and startup apps that apply to all users '
                      'can only be changed by an administrator. Everything else works with normal rights.',
                ),
              ),
              _Faq(
                L.t('Dosyalarım bir yere gönderiliyor mu?', 'Are my files sent anywhere?'),
                L.t(
                  'Hayır. Tarama ve temizlik tamamen bilgisayarında yapılır. Yalnızca, izin verirsen, '
                      'uygulamada beklenmeyen bir hata olduğunda kişisel bilgi içermeyen bir hata raporu gönderilir. '
                      'Bunu Ayarlar’dan kapatabilirsin.',
                  'No. Scanning and cleaning happen entirely on your computer. Only if you allow it, an error report '
                      'without personal information is sent when something unexpected goes wrong in the app. '
                      'You can turn this off in Settings.',
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label, required this.value, required this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.muted),
            const SizedBox(width: 12),
            SizedBox(width: 150, child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.accent))),
            const Icon(Icons.open_in_new, size: 16, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq(this.question, this.answer);

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 24),
      childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      expandedAlignment: Alignment.centerLeft,
      title: Text(question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      children: [Text(answer, style: const TextStyle(color: AppColors.muted, height: 1.5))],
    );
  }
}
