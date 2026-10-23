import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cihaz_bakim/core/i18n.dart';
import 'package:cihaz_bakim/services/android_cleaner.dart';

// Android tarafını (MainActivity.kt) taklit eden sahte kanal ile AndroidCleaner'ın Dart mantığı.

const _day = 86400000;

Map<String, Object?> _media(String uri, String dir, String name, int size, {String kind = 'image', int ageDays = 1}) {
  final t = DateTime.now().millisecondsSinceEpoch - ageDays * _day;
  return {
    'uri': uri,
    'name': name,
    'dir': dir,
    'size': size,
    'modified': t,
    'added': t,
    'taken': t,
    'mime': kind == 'video' ? 'video/mp4' : 'image/jpeg',
    'kind': kind,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('harrier/android');
  final requests = <String>[];

  final files = [
    _media('content://1', 'DCIM/Camera/', 'IMG_1.jpg', 300000),
    _media('content://2', 'Download/', 'IMG_1 (1).jpg', 300000), // 1 ile aynı içerik
    _media('content://3', 'DCIM/Camera/', 'IMG_2.jpg', 300000), // aynı boyut, farklı içerik
    _media('content://4', 'Pictures/Screenshots/', 'shot.png', 2000, ageDays: 200),
    _media('content://5', 'Pictures/Screenshots/', 'yeni.png', 2000, ageDays: 3),
    _media('content://6', 'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/', 'v.mp4', 5000000, kind: 'video'),
  ];

  setUp(() {
    L.apply(AppLanguage.tr);
    requests.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?) ?? {};
      switch (call.method) {
        case 'filesDir':
          return '/data/user/0/dev.oalabs.harrier/files';
        case 'mediaPermission':
          return {'granted': true, 'partial': false, 'location': true};
        case 'storage':
          return {'total': 64000000000, 'free': 14000000000};
        case 'queryMedia':
          final kinds = (args['kinds'] as List).cast<String>();
          final minSize = (args['minSize'] as num).toInt();
          return files.where((f) => kinds.contains(f['kind']) && (f['size'] as int) >= minSize).toList();
        case 'hash':
          // 1 ve 2 aynı içerik; diğerleri farklı
          return [for (final u in (args['uris'] as List).cast<String>()) u == 'content://2' ? 'h1' : 'h${u.split('//').last}'];
        case 'request':
          requests.add('${args['type']}:${(args['uris'] as List).join(',')}');
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('ayar ve hata günlüğü uygulamanın klasöründe', () async {
    final c = await AndroidCleaner.create();
    expect(c.settingsPath, '/data/user/0/dev.oalabs.harrier/files/settings.json');
    expect(c.errorLogPath, '/data/user/0/dev.oalabs.harrier/files/errors.log');
    expect(c.isDesktop, isFalse);
    expect(c.needsMediaPermission, isTrue);
  });

  test('kopya bulucu yalnızca içeriği aynı olanları gruplar ve kopyayı çöp kutusuna taşır', () async {
    final c = await AndroidCleaner.create();
    final groups = await c.findDuplicates(['images'], minSize: 1024);
    expect(groups, isNotNull);
    expect(groups!.length, 1);
    final paths = groups.single.files.map((f) => f.path).toSet();
    expect(paths, {'DCIM/Camera/IMG_1.jpg', 'Download/IMG_1 (1).jpg'});

    final toDelete = groups.single.files.where((f) => f.selected).map((f) => f.path).toList();
    expect(toDelete.length, 1);
    expect(await c.deleteFiles(toDelete), 1);
    expect(requests.single, startsWith('trash:'));
  });

  test('gereksiz dosyalar: eski ekran görüntüsü seçili, yenisi listede değil, WhatsApp videosu seçili değil', () async {
    final c = await AndroidCleaner.create();
    final junk = await c.scanJunk();
    expect(junk, isNotNull);
    final shots = junk!.firstWhere((j) => j.id == 'shots');
    expect(shots.fileCount, 1);
    expect(shots.selected, isTrue);
    final wa = junk.firstWhere((j) => j.id == 'wa_video');
    expect(wa.selected, isFalse);

    final r = await c.cleanJunk([shots]);
    expect(r.freedBytes, 2000);
    expect(requests.single, 'delete:content://4');
  });

  test('disk haritası: üst düzey klasörler ve "diğer"; klasörün içine inilebiliyor', () async {
    final c = await AndroidCleaner.create();
    final top = await c.folderUsage(AndroidCleaner.storageRoot);
    final names = top!.map((u) => u.name).toList();
    expect(names, containsAll(['DCIM', 'Download', 'Pictures', 'Android']));
    expect(names.any((n) => n.startsWith('Uygulamalar')), isTrue);
    final dcim = top.firstWhere((u) => u.name == 'DCIM');
    expect(dcim.isDir, isTrue);
    expect(dcim.bytes, 600000);

    final inner = await c.folderUsage(dcim.path);
    expect(inner!.single.name, 'Camera');
    expect(inner.single.path, '${AndroidCleaner.storageRoot}/DCIM/Camera');
  });
}
