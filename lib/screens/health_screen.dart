import 'package:flutter/material.dart';

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
      title: 'Pil ve Sağlık',
      subtitle: 'Pilin ve disklerin durumu. Bilgiler Windows’un kendi kayıtlarından okunur.',
      children: [
        if (state.service.isSample) const SampleBanner(),
        if (!state.healthLoaded)
          const BusyCard(text: 'Pil ve disk bilgileri okunuyor…')
        else ...[
          _BatteryCard(battery: state.battery, onReport: state.service.isSample ? null : state.service.openBatteryReport),
          if (state.admin == false && missingDetails)
            const AdminBanner(message: 'Disk sıcaklığı ve yıpranma bilgisi için yönetici izni gerekir.'),
          for (final d in disks) _DiskCard(disk: d),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: state.healthBusy ? null : state.loadHealth,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Yenile'),
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
    if (b == null) {
      return const EmptyState(
        icon: Icons.power_outlined,
        text: 'Bu bilgisayarda pil bulunamadı. Masaüstü bilgisayarlarda bu bölüm boş kalır.',
      );
    }
    final pct = (b.health * 100).round().clamp(0, 100);
    final (label, color) = pct >= 80
        ? ('İyi durumda', AppColors.keepText)
        : pct >= 60
            ? ('Yıpranmış', AppColors.warnText)
            : ('Değiştirmeyi düşünebilirsiniz', const Color(0xFFB91C1C));
    String wh(int mwh) => '${(mwh / 1000).toStringAsFixed(1).replaceAll('.', ',')} Wh';
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
                        Text('%$pct', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                        const Text('pil sağlığı', style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
                  _InfoLine('İlk günkü kapasite', wh(b.designCapacity)),
                  _InfoLine('Bugünkü tam şarj kapasitesi', wh(b.fullChargeCapacity)),
                  if (b.cycleCount != null && b.cycleCount! > 0) _InfoLine('Şarj döngüsü', formatCount(b.cycleCount!)),
                  if (b.chemistry.isNotEmpty) _InfoLine('Pil tipi', b.chemistry),
                  const SizedBox(height: 10),
                  const Text(
                    'Pil sağlığı, pilin bugün tutabildiği enerjinin ilk günkü kapasitesine oranıdır. '
                    'Zamanla düşmesi normaldir.',
                    style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
                  ),
                  if (report != null) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: report,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Ayrıntılı pil raporunu aç'),
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
      'healthy' => ('Sağlıklı', AppColors.keepBg, AppColors.keepText),
      'warning' => ('Uyarı', AppColors.warnBg, AppColors.warnText),
      'unhealthy' => ('Sorunlu', const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      _ => ('Bilinmiyor', const Color(0xFFF3F4F6), const Color(0xFF374151)),
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
                    if (disk.temperature != null) _Metric('Sıcaklık', '${disk.temperature} °C'),
                    if (disk.wear != null) _Metric('Yıpranma', '%${disk.wear}'),
                    if (disk.powerOnHours != null) _Metric('Çalışma süresi', '${formatCount(disk.powerOnHours!)} saat'),
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
