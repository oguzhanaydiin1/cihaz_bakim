import 'dart:io';

enum AppPlatform { windows, android, other }

AppPlatform get currentPlatform {
  if (Platform.isWindows) return AppPlatform.windows;
  if (Platform.isAndroid) return AppPlatform.android;
  return AppPlatform.other;
}
