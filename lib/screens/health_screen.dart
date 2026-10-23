import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppScope.read(context);
      if (!state.healthLoaded) state.loadHealth();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final disks = state.disks ?? [];
    final missingDetails = disks.isNotEmpty && disks.every((d) => d.temperature == null && d.wear == null);

    return ModulePage(
      title: L.t('Pil ve Sağlık', 'Battery & Health'),
      subtitle: state.service.isDesktop || state.service.isSample
          ? L.t('Pilin ve disklerin durumu. Bilgiler Windows’un kendi kayıtlarından okunur.', 'The condition of your battery and disks, read from Windows’ own records.')
          : L.t('Pilin durumu. Bilgiler Android’in kendi kayıtlarından okunur.', 'Your battery’s condition, read from Android’s own records.'),
      children: [
        if (state.service.isSample) const SampleBanner(),
        if (!state.healthLoaded)
          BusyCard(text: L.t('Pil ve disk bilgileri okunuyor…', 'Reading battery and disk information…'))
        else ...[
          _BatteryCard(battery: state.battery, onReport: state.service.isDesktop ? state.service.openBatteryReport : null),
          if (state.service.isDesktop && state.admin == false && missingDetails)
            AdminBanner(message: L.t('Disk sıcaklığı ve yıpranma bilgisi için yönetici izni gerekir.', 'Disk temperature and wear need administrator rights.')),
          for (final d in disks) _DiskCard(disk: d),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: state.healthBusy ? null : state.loadHealth,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(L.t('Yenile', 'Refresh')),
            ),
          ),
        ],
      ],
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({required this.battery, required this.onReport});

  final BatteryInfo? battery;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final b = battery;
    if (b != null && !b.hasCapacity && b.level != null) return _PhoneBatteryCard(battery: b);
    if (b == null) {
      return EmptyState(
        icon: Icons.power_outlined,
        text: L.t('Bu bilgisayarda pil bulunamadı. Masaüstü bilgisayarlarda bu bölüm boş kalır.', 'No battery found. This section stays empty on desktop computers.'),
      );
    }
    final pct = (b.health * 100).round().clamp(0, 100);
    final (label, color) = pct >= 80
        ? (L.t('İyi durumda', 'Good condition'), AppColors.keepText)
        : pct >= 60
            ? (L.t('Yıpranmış', 'Worn'), AppColors.warnText)
            : (L.t('Değiştirmeyi düşünebilirsiniz', 'Consider replacing it'), const Color(0xFFB91C1C));
    String wh(int mwh) => '${formatDecimal(mwh / 1000, 1)} Wh';
    final report = onReport;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 32,
          runSpacing: 20,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: pct / 100,
                    strokeWidth: 14,
                    color: color,
                    backgroundColor: AppColors.line,
                    strokeCap: StrokeCap.butt,
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(L.t('%$pct', '$pct%'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                        Text(L.t('pil sağlığı', 'battery health'), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                  const SizedBox(height: 10),
                  _InfoLine(L.t('İlk günkü kapasite', 'Original capacity'), wh(b.designCapacity)),
                  _InfoLine(L.t('Bugünkü tam şarj kapasitesi', 'Full charge capacity today'), wh(b.fullChargeCapacity)),
                  if (b.cycleCount != null && b.cycleCount! > 0) _InfoLine(L.t('Şarj döngüsü', 'Charge cycles'), formatCount(b.cycleCount!)),
                  if (b.chemistry.isNotEmpty) _InfoLine(L.t('Pil tipi', 'Battery type'), b.chemistry),
                  const SizedBox(height: 10),
                  Text(
                    L.t('Pil sağlığı, pilin bugün tutabildiği enerjinin ilk günkü kapasitesine oranıdır. Zamanla düşmesi normaldir.',
                        'Battery health is how much energy the battery can hold today compared with when it was new. It’s normal for it to drop over time.'),
                    style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
                  ),
                  if (report != null) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: report,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(L.t('Ayrıntılı pil raporunu aç', 'Open detailed battery report')),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiskCard extends StatelessWidget {
  const _DiskCard({required this.disk});

  final DiskHealth disk;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (disk.status.toLowerCase()) {
      'healthy' => (L.t('Sağlıklı', 'Healthy'), AppColors.keepBg, AppColors.keepText),
      'warning' => (L.t('Uyarı', 'Warning'), AppColors.warnBg, AppColors.warnText),
      'unhealthy' => (L.t('Sorunlu', 'Unhealthy'), const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      _ => (L.t('Bilinmiyor', 'Unknown'), const Color(0xFFF3F4F6), const Color(0xFF374151)),
    };
    final type = [
      if (disk.mediaType.isNotEmpty && disk.mediaType != 'Unspecified') disk.mediaType,
      if (disk.busType.isNotEmpty) disk.busType,
      if (disk.sizeBytes > 0) formatBytes(disk.sizeBytes),
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage_outlined, color: AppColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(disk.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Tag(label, background: bg, foreground: fg),
              ],
            ),
            if (type.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Text(type, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ),
            ],
            if (disk.temperature != null || disk.wear != null || disk.powerOnHours != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Wrap(
                  spacing: 28,
                  runSpacing: 8,
                  children: [
                    if (disk.temperature != null) _Metric(L.t('Sıcaklık', 'Temperature'), '${disk.temperature} °C'),
                    if (disk.wear != null) _Metric(L.t('Yıpranma', 'Wear'), L.t('%${disk.wear}', '${disk.wear}%')),
                    if (disk.powerOnHours != null) _Metric(L.t('Çalışma süresi', 'Power-on time'), L.t('${formatCount(disk.powerOnHours!)} saat', '${formatCount(disk.powerOnHours!)} hours')),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// Android: Android pilin ilk günkü kapasitesini uygulamalara göstermez. Bunun yerine sistemin
/// kendi sağlık değerlendirmesi, sıcaklık, şarj ve (Android 14+) şarj döngüsü gösterilir.
class _PhoneBatteryCard extends StatelessWidget {
  const _PhoneBatteryCard({required this.battery});

  final BatteryInfo battery;

  @override
  Widget build(BuildContext context) {
    final b = battery;
    final level = (b.level ?? 0).clamp(0, 100);
    final temp = b.temperature;
    final (label, color) = switch (b.status) {
      'good' => (L.t('Android’e göre pil sağlıklı', 'Android reports the battery as healthy'), AppColors.keepText),
      'overheat' => (L.t('Pil aşırı ısınmış', 'The battery is overheating'), const Color(0xFFB91C1C)),
      'cold' => (L.t('Pil çok soğuk', 'The battery is too cold'), AppColors.warnText),
      'dead' || 'failure' || 'overvoltage' => (L.t('Android pilde sorun bildiriyor', 'Android reports a battery problem'), const Color(0xFFB91C1C)),
      _ => (L.t('Pil durumu bilinmiyor', 'Battery condition unknown'), AppColors.muted),
    };
    final hot = temp != null && temp >= 40;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 32,
          runSpacing: 20,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: level / 100,
                    strokeWidth: 14,
                    backgroundColor: AppColors.line,
                    strokeCap: StrokeCap.butt,
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(L.t('%$level', '$level%'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                        Text(
                          b.charging == true ? L.t('şarj oluyor', 'charging') : L.t('şarj', 'charge'),
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                  const SizedBox(height: 10),
                  if (temp != null)
                    _InfoLine(L.t('Sıcaklık', 'Temperature'), '${formatDecimal(temp, 1)} °C${hot ? L.t(' · sıcak', ' · hot') : ''}'),
                  if (b.cycleCount != null && b.cycleCount! > 0) _InfoLine(L.t('Şarj döngüsü', 'Charge cycles'), formatCount(b.cycleCount!)),
                  if (b.estimatedFullMah != null && b.estimatedFullMah! > 0)
                    _InfoLine(L.t('Tahmini tam şarj kapasitesi', 'Estimated full charge capacity'), '${formatCount(b.estimatedFullMah!)} mAh'),
                  if (b.voltageMv != null && b.voltageMv! > 0) _InfoLine(L.t('Gerilim', 'Voltage'), '${formatDecimal(b.voltageMv! / 1000, 2)} V'),
                  if (b.chemistry.isNotEmpty) _InfoLine(L.t('Pil tipi', 'Battery type'), b.chemistry),
                  const SizedBox(height: 10),
                  Text(
                    L.t('Android, pilin ilk günkü kapasitesini uygulamalara göstermez; bu yüzden yüzde olarak pil sağlığı hesaplanamaz. Tahmini kapasite, anlık yük ve şarj yüzdesinden hesaplanır ve şarj %20’nin üzerindeyken daha doğrudur.',
                        'Android doesn’t show apps the battery’s original capacity, so a battery health percentage can’t be calculated. The estimated capacity is worked out from the current charge and is more accurate above 20%.'),
                    style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

