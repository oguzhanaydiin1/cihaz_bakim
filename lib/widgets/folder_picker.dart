import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../services/error_reporter.dart';

/// Windows'un klasör seçme penceresini açar. Vazgeçilirse null döner.
///
/// [initialDirectory] yalnızca gerçekten varsa kullanılır: Windows, var olmayan bir
/// başlangıç klasörüyle pencereyi hiç açmaz (ör. OneDrive yedeklemesi açıkken
/// C:\Users\<ad>\Pictures bulunmaz). Başlangıç klasörüyle açılamazsa onsuz yeniden denenir.
Future<String?> pickFolder(String title, {String? initialDirectory}) async {
  final start = initialDirectory != null && initialDirectory.trim().isNotEmpty && Directory(initialDirectory).existsSync()
      ? initialDirectory
      : null;
  try {
    return await FilePicker.getDirectoryPath(dialogTitle: title, initialDirectory: start);
  } catch (e, st) {
    if (start == null) {
      ErrorReporter.record(e, st);
      return null;
    }
  }
  try {
    return await FilePicker.getDirectoryPath(dialogTitle: title);
  } catch (e, st) {
    ErrorReporter.record(e, st);
    return null;
  }
}
