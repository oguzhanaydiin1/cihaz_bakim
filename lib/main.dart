import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'services/cleaner_service.dart';
import 'services/error_reporter.dart';
import 'state/app_state.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(await CleanerService.start());
  ErrorReporter.init(
    logPath: state.service.errorLogPath,
    canSend: () => state.settings.sendErrorReports,
    installId: () => state.settings.installId,
  );
  state.init();
  runApp(CihazBakimApp(state: state));
}

class CihazBakimApp extends StatelessWidget {
  const CihazBakimApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Harrier Cleaner',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      ),
    );
  }
}
