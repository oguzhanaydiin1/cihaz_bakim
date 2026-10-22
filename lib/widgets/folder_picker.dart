import 'package:file_picker/file_picker.dart';

/// Windows'un klasör seçme penceresini açar. Vazgeçilirse null döner.
Future<String?> pickFolder(String title, {String? initialDirectory}) async {
  try {
    return await FilePicker.getDirectoryPath(dialogTitle: title, initialDirectory: initialDirectory);
  } catch (_) {
    return null;
  }
}
