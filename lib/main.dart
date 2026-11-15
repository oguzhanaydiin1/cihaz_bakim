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

class CihazBakimApp extends StatefulWidget {
  const CihazBakimApp({super.key, required this.state});

  final AppState state;

  @override
  State<CihazBakimApp> createState() => _CihazBakimAppState();
}

class _CihazBakimAppState extends State<CihazBakimApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeTick.addListener(_repaintAll);
  }

  @override
  void dispose() {
    themeTick.removeListener(_repaintAll);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (widget.state.settings.theme == 'system') applyThemeMode('system');
  }

  /// Renkler AppColors'tan doğrudan okunduğu için tema değişince her öğeyi yeniden çiz
  /// (sayfa ve kaydırma konumu korunur).
  void _repaintAll() {
    if (!mounted) return;
    setState(() {});
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (context as Element).visitChildren(mark);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: 'Harrier Cleaner',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      ),
    );
  }
}
