import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cihaz_bakim/core/i18n.dart';
import 'package:cihaz_bakim/models/models.dart';
import 'package:cihaz_bakim/services/android_cleaner.dart';

// Android emülatöründe çalışır (.github/workflows/android-emulator.yml). Emülatöre önceden
// DCIM/Camera/hc_a.jpg ve hc_b.jpg (aynı içerik, konumlu) ile hc_big.jpg (büyük) konur;
// uygulama tüm izinleri verilmiş olarak kurulur.
//
// HC_WRITE=true (Android 10): onay penceresi çıkmadığı için yazma işlemleri de denenir.

const writable = bool.fromEnvironment('HC_WRITE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late AndroidCleaner c;

  setUpAll(() async {
    L.apply(AppLanguage.tr);
    c = await AndroidCleaner.create();
  });

  testWidgets('cihaz bilgileri okunuyor', (tester) async {
    final storage = await c.storageInfo();
    expect(storage, isNotNull);
    expect(storage!.total, greaterThan(0));

    final sys = await c.systemInfo();
    expect(sys, isNotNull);
    expect(sys!.cores, greaterThan(0));
    expect(sys.totalRam, greaterThan(0));
    expect(sys.osName, startsWith('Android'));

    final battery = await c.batteryInfo();
    expect(battery?.level, isNotNull);

    final live = await c.liveStats().first.timeout(const Duration(seconds: 15));
    expect(live.ramAvailable, greaterThan(0));

    expect(await c.permissions(), isNotNull);
    expect(await c.installedApps(), isA<List<InstalledApp>>());
    expect(c.settingsPath, contains('dev.oalabs.harrier'));
  });

  testWidgets('medya izni, kopyalar, konum ve disk haritası', (tester) async {
    final access = await c.mediaAccess();
    expect(access.granted, isTrue);
    expect(access.location, isTrue);

    final dups = await c.findDuplicates(['images'], minSize: 1);
    expect(dups, isNotNull);
    expect(
      dups!.any((g) => g.files.any((f) => f.path.endsWith('hc_a.jpg')) && g.files.any((f) => f.path.endsWith('hc_b.jpg'))),
      isTrue,
      reason: 'hc_a ve hc_b kopya olarak bulunmalı: ${dups.map((g) => g.files.map((f) => f.path).toList()).toList()}',
    );

    final gps = await c.findLocationPhotos('');
    final hit = gps!.where((p) => p.path.endsWith('hc_a.jpg')).toList();
    expect(hit, isNotEmpty, reason: 'konumlu fotoğraflar: ${gps.map((p) => p.path).toList()}');
    expect(hit.first.latitude!, closeTo(41.015, 0.01));
    expect(hit.first.longitude!, closeTo(28.979, 0.01));

    final usage = await c.folderUsage(AndroidCleaner.storageRoot);
    expect(usage!.any((u) => u.name == 'DCIM' && u.isDir), isTrue);
    final dcim = await c.folderUsage('${AndroidCleaner.storageRoot}/DCIM');
    expect(dcim!.any((u) => u.name == 'Camera'), isTrue);

    final photos = await c.findPhotos('', minSize: 1024 * 1024);
    expect(photos!.any((p) => p.path.endsWith('hc_big.jpg')), isTrue);
  });

  testWidgets('yazma: konum silme, küçültme, kopyayı silme (Android 10)', (tester) async {
    final gps = await c.findLocationPhotos('');
    final a = gps!.firstWhere((p) => p.path.endsWith('hc_a.jpg'));
    final (cleaned, failed) = await c.removeLocation([a.path]);
    expect(failed, 0);
    expect(cleaned, 1);
    final after = await c.findLocationPhotos('');
    expect(after!.any((p) => p.path.endsWith('hc_a.jpg')), isFalse, reason: 'konum silinmiş olmalı');

    final photos = await c.findPhotos('', minSize: 1024 * 1024);
    final big = photos!.firstWhere((p) => p.path.endsWith('hc_big.jpg'));
    final r = await c.compressPhotos([big.path], const CompressOptions(quality: 75));
    expect(r, isNotNull);
    expect(r!.failed, 0);
    expect(r.compressed, 1);
    expect(r.savedBytes, greaterThan(0));
    final all = await c.findPhotos('', minSize: 1);
    final names = all!.map((p) => '${p.path} ${p.sizeBytes}').toList();
    final inPlace = all.where((p) => p.path == big.path).toList();
    expect(inPlace.length, 1, reason: 'küçültülmüş hâli aynı adla yerinde olmalı: $names');
    expect(inPlace.single.sizeBytes, lessThan(big.sizeBytes), reason: '$names');
    final backup = all.where((p) => p.path == 'Pictures/Harrier Cleaner Yedek/hc_big.jpg').toList();
    expect(backup.length, 1, reason: 'orijinal yedek albümünde olmalı: $names');
    expect(backup.single.sizeBytes, big.sizeBytes, reason: 'yedek orijinalle aynı boyutta olmalı');

    final dups = await c.findDuplicates(['images'], minSize: 1);
    final b = dups!.expand((g) => g.files).where((f) => f.path.endsWith('hc_b.jpg')).toList();
    if (b.isNotEmpty) expect(await c.deleteFiles([b.first.path]), 1);
  }, skip: !writable);
}
