import 'package:flutter/material.dart';

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
      return const ModulePage(
        title: 'Sistem Bilgisi',
        children: [BusyCard(text: 'Donanım bilgileri okunuyor…')],
      );
    }

    final ram = state.ramPercent;
    final usedRam = info != null && live != null ? info.totalRam - live.ramAvailable : null;
    final gpuName = info != null && info.gpus.isNotEmpty ? info.gpus.first.name : '';
    final temp = live?.temperature;

    final tiles = <Widget>[
      _LiveTile(
        title: 'İşlemci',
        value: live == null ? '—' : '%${live.cpuPercent.round()}',
        detail: live != null && live.cpuMhz > 0 ? '${_ghz(live.cpuMhz)} GHz' : 'Kullanım',
        history: state.cpuHistory,
      ),
      _LiveTile(
        title: 'Bellek',
        value: ram == null ? '—' : '%${ram.round()}',
        detail: usedRam != null && info != null ? '${formatBytes(usedRam)} / ${formatBytes(info.totalRam)}' : 'Kullanım',
        history: state.ramHistory,
      ),
      _LiveTile(
        title: 'Ekran kartı',
        value: live?.gpuPercent == null ? '—' : '%${live!.gpuPercent!.round()}',
        detail: gpuName.isNotEmpty ? gpuName : 'Kullanım',
        history: state.gpuHistory,
      ),
      _LiveTile(
        title: 'Sıcaklık',
        value: temp == null ? '—' : '${temp.toStringAsFixed(0)} °C',
        detail: temp == null ? 'Bu bilgisayar paylaşmıyor' : 'Termal bölge, yaklaşık',
      ),
      _LiveTile(
        title: 'Disk',
        value: live == null ? '—' : _rate(live.diskRead + live.diskWrite),
        detail: live == null ? 'Okuma ve yazma' : 'Okuma ${_rate(live.diskRead)} · Yazma ${_rate(live.diskWrite)}',
      ),
      _LiveTile(
        title: 'Ağ',
        value: live == null ? '—' : _rate(live.netDown),
        detail: live == null ? 'İndirme ve yükleme' : 'İndirme · Yükleme ${_rate(live.netUp)}',
      ),
    ];

    return ModulePage(
      title: 'Sistem Bilgisi',
      subtitle: 'Bilgisayarınızın donanımı ve anlık durumu. Değerler birkaç saniyede bir yenilenir.',
      children: [
        if (state.service.isSample) const SampleBanner(),
        Wrap(spacing: 14, runSpacing: 14, children: [for (final t in tiles) SizedBox(width: 250, child: t)]),
        if (info != null) _HardwareCard(info: info),
        if (live != null && live.topMemory.isNotEmpty) _TopMemoryCard(items: live.topMemory, totalRam: info?.totalRam ?? 0),
        const Text(
          'İşlemci sıcaklığı hakkında: Windows işlemcinin kendi sıcaklığını paylaşmaz. Burada gösterilen, '
          'anakartın bildirdiği termal bölge sıcaklığıdır; birçok bilgisayarda hiç bildirilmez ya da işlemciden '
          'düşük çıkar.',
          style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5),
        ),
      ],
    );
  }

  static String _ghz(int mhz) => (mhz / 1000).toStringAsFixed(2).replaceAll('.', ',');

  static String _rate(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}/sn';
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
                  label: '$title son ${h.length} ölçüm',
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
      if (d.inDays > 0) '${d.inDays} gün',
      if (d.inHours % 24 > 0) '${d.inHours % 24} saat',
      '${d.inMinutes % 60} dakika',
    ];
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final boot = info.bootTime;
    final device = [info.manufacturer, info.model].where((s) => s.trim().isNotEmpty).join(' ');
    final rows = <(String, String)>[
      if (device.isNotEmpty) ('Cihaz', device),
      ('İşlemci', info.cpuName),
      if (info.cores > 0) ('Çekirdek', '${info.cores} çekirdek, ${info.threads} iş parçacığı'),
      if (info.maxMhz > 0) ('Temel hız', '${(info.maxMhz / 1000).toStringAsFixed(2).replaceAll('.', ',')} GHz'),
      ('Bellek', formatBytes(info.totalRam)),
      for (final g in info.gpus) ('Ekran kartı', g.memoryBytes > 0 ? '${g.name} · ${formatBytes(g.memoryBytes)}' : g.name),
      ('İşletim sistemi', info.osBuild.isNotEmpty && info.osBuild != '-' ? '${info.osName} (derleme ${info.osBuild})' : info.osName),
      if (boot != null) ('Açık kalma süresi', _uptime(boot)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Donanım', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
            const Text('En çok bellek kullanan programlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
              const Text(
                'Aynı adlı işlemler toplanarak gösterilir; parantez içindeki sayı işlem adedidir.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
