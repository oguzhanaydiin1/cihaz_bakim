import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  AppState? _state;

  @override
  void initState() {
    super.initState();
    // Ölçüm yalnızca bu ekran açıkken çalışır.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _state = AppScope.read(context)..startSystemMonitor();
    });
  }

  @override
  void dispose() {
    _state?.stopSystemMonitor();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final info = state.systemInfo;
    final live = state.live;

    if (info == null && live == null) {
      return ModulePage(
        title: L.t('Sistem Bilgisi', 'System Info'),
        children: [BusyCard(text: L.t('Donanım bilgileri okunuyor…', 'Reading hardware information…'))],
      );
    }

    final ram = state.ramPercent;
    final usedRam = info != null && live != null ? info.totalRam - live.ramAvailable : null;
    final gpuName = info != null && info.gpus.isNotEmpty ? info.gpus.first.name : '';
    final temp = live?.temperature;

    final tiles = <Widget>[
      _LiveTile(
        title: L.t('İşlemci', 'Processor'),
        value: live == null ? '—' : _pct(live.cpuPercent),
        detail: live != null && live.cpuMhz > 0 ? '${_ghz(live.cpuMhz)} GHz' : L.t('Kullanım', 'Usage'),
        history: state.cpuHistory,
      ),
      _LiveTile(
        title: L.t('Bellek', 'Memory'),
        value: ram == null ? '—' : _pct(ram),
        detail: usedRam != null && info != null ? '${formatBytes(usedRam)} / ${formatBytes(info.totalRam)}' : L.t('Kullanım', 'Usage'),
        history: state.ramHistory,
      ),
      _LiveTile(
        title: L.t('Ekran kartı', 'Graphics'),
        value: live?.gpuPercent == null ? '—' : _pct(live!.gpuPercent!),
        detail: gpuName.isNotEmpty ? gpuName : L.t('Kullanım', 'Usage'),
        history: state.gpuHistory,
      ),
      _LiveTile(
        title: L.t('Sıcaklık', 'Temperature'),
        value: temp == null ? '—' : '${temp.toStringAsFixed(0)} °C',
        detail: temp == null ? L.t('Bu bilgisayar paylaşmıyor', 'Not reported by this PC') : L.t('Termal bölge, yaklaşık', 'Thermal zone, approximate'),
      ),
      _LiveTile(
        title: 'Disk',
        value: live == null ? '—' : _rate(live.diskRead + live.diskWrite),
        detail: live == null ? L.t('Okuma ve yazma', 'Read and write') : L.t('Okuma ${_rate(live.diskRead)} · Yazma ${_rate(live.diskWrite)}', 'Read ${_rate(live.diskRead)} · Write ${_rate(live.diskWrite)}'),
      ),
      _LiveTile(
        title: L.t('Ağ', 'Network'),
        value: live == null ? '—' : _rate(live.netDown),
        detail: live == null ? L.t('İndirme ve yükleme', 'Download and upload') : L.t('İndirme · Yükleme ${_rate(live.netUp)}', 'Download · Upload ${_rate(live.netUp)}'),
      ),
    ];

    return ModulePage(
      title: L.t('Sistem Bilgisi', 'System Info'),
      subtitle: L.t('Bilgisayarınızın donanımı ve anlık durumu. Değerler birkaç saniyede bir yenilenir.', 'Your computer’s hardware and what it’s doing right now. Values refresh every few seconds.'),
      children: [
        if (state.service.isSample) const SampleBanner(),
        Wrap(spacing: 14, runSpacing: 14, children: [for (final t in tiles) SizedBox(width: 250, child: t)]),
        if (info != null) _HardwareCard(info: info),
        if (live != null && live.topMemory.isNotEmpty) _TopMemoryCard(items: live.topMemory, totalRam: info?.totalRam ?? 0),
        Text(
          L.t('İşlemci sıcaklığı hakkında: Windows işlemcinin kendi sıcaklığını paylaşmaz. Burada gösterilen, anakartın bildirdiği termal bölge sıcaklığıdır; birçok bilgisayarda hiç bildirilmez ya da işlemciden düşük çıkar.',
              'About processor temperature: Windows doesn’t share the processor’s own temperature. What’s shown here is the thermal zone temperature reported by the motherboard; many computers don’t report it, or it reads lower than the processor.'),
          style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5),
        ),
      ],
    );
  }

  static String _ghz(int mhz) => formatDecimal(mhz / 1000, 2);

  static String _pct(double v) => L.t('%${v.round()}', '${v.round()}%');

  static String _rate(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}${L.t('/sn', '/s')}';
}

/// Başlık, büyük değer, açıklama ve isteğe bağlı küçük çizgi grafik.
class _LiveTile extends StatelessWidget {
  const _LiveTile({required this.title, required this.value, required this.detail, this.history});

  final String title;
  final String value;
  final String detail;
  final List<double>? history;

  @override
  Widget build(BuildContext context) {
    final h = history;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            if (h != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: Semantics(
                  label: L.t('$title son ${h.length} ölçüm', '$title, last ${h.length} readings'),
                  child: CustomPaint(painter: _SparklinePainter(h)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 0-100 aralığında sabit ölçekli, tek serilik çizgi grafik.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter(List<double> values) : values = List.of(values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    // Taban çizgisi
    final base = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), base);
    if (values.length < 2) return;

    // Noktalar sağa yaslanır: grafik dolana kadar soldan boş kalır.
    final step = size.width / (AppState.historyLength - 1);
    final startX = size.width - step * (values.length - 1);
    Offset point(int i) {
      final v = values[i].clamp(0.0, 100.0);
      return Offset(startX + step * i, size.height - 1 - (size.height - 2) * v / 100);
    }

    final line = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = point(i);
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(point(values.length - 1).dx, size.height)
      ..lineTo(startX, size.height)
      ..close();

    canvas.drawPath(area, Paint()..color = const Color(0x1F1D4ED8));
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => true;
}

class _HardwareCard extends StatelessWidget {
  const _HardwareCard({required this.info});

  final SystemInfo info;

  String _uptime(DateTime boot) {
    final d = DateTime.now().difference(boot);
    final parts = <String>[
      if (d.inDays > 0) L.t('${d.inDays} gün', '${d.inDays} d'),
      if (d.inHours % 24 > 0) L.t('${d.inHours % 24} saat', '${d.inHours % 24} h'),
      L.t('${d.inMinutes % 60} dakika', '${d.inMinutes % 60} min'),
    ];
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final boot = info.bootTime;
    final device = [info.manufacturer, info.model].where((s) => s.trim().isNotEmpty).join(' ');
    final rows = <(String, String)>[
      if (device.isNotEmpty) (L.t('Cihaz', 'Device'), device),
      (L.t('İşlemci', 'Processor'), info.cpuName),
      if (info.cores > 0) (L.t('Çekirdek', 'Cores'), L.t('${info.cores} çekirdek, ${info.threads} iş parçacığı', '${info.cores} cores, ${info.threads} threads')),
      if (info.maxMhz > 0) (L.t('Temel hız', 'Base speed'), '${formatDecimal(info.maxMhz / 1000, 2)} GHz'),
      (L.t('Bellek', 'Memory'), formatBytes(info.totalRam)),
      for (final g in info.gpus) (L.t('Ekran kartı', 'Graphics'), g.memoryBytes > 0 ? '${g.name} · ${formatBytes(g.memoryBytes)}' : g.name),
      (L.t('İşletim sistemi', 'Operating system'), info.osBuild.isNotEmpty && info.osBuild != '-' ? L.t('${info.osName} (derleme ${info.osBuild})', '${info.osName} (build ${info.osBuild})') : info.osName),
      if (boot != null) (L.t('Açık kalma süresi', 'Uptime'), _uptime(boot)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L.t('Donanım', 'Hardware'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 150, child: Text(label, style: const TextStyle(color: AppColors.muted))),
                    Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopMemoryCard extends StatelessWidget {
  const _TopMemoryCard({required this.items, required this.totalRam});

  final List<ProcessMemory> items;
  final int totalRam;

  @override
  Widget build(BuildContext context) {
    final max = items.fold<int>(1, (m, p) => p.bytes > m ? p.bytes : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L.t('En çok bellek kullanan programlar', 'Programs using the most memory'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final p in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 190,
                      child: Text(
                        p.count > 1 ? '${p.name} (${p.count})' : p.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: p.bytes / max,
                          minHeight: 8,
                          backgroundColor: AppColors.line,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: Text(formatBytes(p.bytes), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            if (totalRam > 0) ...[
              const SizedBox(height: 6),
              Text(
                L.t('Aynı adlı işlemler toplanarak gösterilir; parantez içindeki sayı işlem adedidir.', 'Processes with the same name are combined; the number in brackets is how many there are.'),
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
