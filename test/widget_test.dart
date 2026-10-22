import 'package:flutter_test/flutter_test.dart';

import 'package:cihaz_bakim/core/format.dart';
import 'package:cihaz_bakim/main.dart';
import 'package:cihaz_bakim/services/sample_cleaner.dart';
import 'package:cihaz_bakim/state/app_state.dart';

void main() {
  test('formatBytes Türkçe biçim kullanır', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(4 * 1024 * 1024 + 200 * 1024), '4,2 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024 ~/ 2), '1,50 GB');
  });

  testWidgets('Akıllı Tarama ekranı açılır', (tester) async {
    final state = AppState(SampleCleaner());
    await tester.pumpWidget(CihazBakimApp(state: state));
    expect(find.text('Akıllı Tarama'), findsWidgets);
  });
}
