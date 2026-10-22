import 'package:flutter_test/flutter_test.dart';

import 'package:cihaz_bakim/core/format.dart';
import 'package:cihaz_bakim/core/i18n.dart';
import 'package:cihaz_bakim/main.dart';
import 'package:cihaz_bakim/services/sample_cleaner.dart';
import 'package:cihaz_bakim/services/updater.dart';
import 'package:cihaz_bakim/state/app_state.dart';

void main() {
  test('formatBytes Türkçe biçim kullanır', () {
    L.apply(AppLanguage.tr);
    expect(formatBytes(512), '512 B');
    expect(formatBytes(4 * 1024 * 1024 + 200 * 1024), '4,2 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024 ~/ 2), '1,50 GB');
  });

  test('formatBytes İngilizce biçim kullanır', () {
    L.apply(AppLanguage.en);
    expect(formatBytes(4 * 1024 * 1024 + 200 * 1024), '4.2 MB');
    expect(formatCount(12345), '12,345');
    L.apply(AppLanguage.tr);
    expect(formatCount(12345), '12.345');
  });

  test('sürüm karşılaştırma', () {
    expect(Updater.compareVersions('0.10.0', '0.9.2'), 1);
    expect(Updater.compareVersions('v1.0.0', '1.0.0'), 0);
    expect(Updater.compareVersions('0.1.0', '0.1.1'), -1);
  });

  testWidgets('Akıllı Tarama ekranı açılır', (tester) async {
    L.apply(AppLanguage.tr);
    final state = AppState(SampleCleaner());
    await tester.pumpWidget(CihazBakimApp(state: state));
    expect(find.text('Akıllı Tarama'), findsWidgets);
  });

  testWidgets('İngilizce arayüz', (tester) async {
    L.apply(AppLanguage.en);
    final state = AppState(SampleCleaner());
    await tester.pumpWidget(CihazBakimApp(state: state));
    expect(find.text('Smart Scan'), findsWidgets);
    expect(find.text('Akıllı Tarama'), findsNothing);
    L.apply(AppLanguage.tr);
  });
}
