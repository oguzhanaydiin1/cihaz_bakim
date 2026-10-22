import 'i18n.dart';

String _dec(String s) => L.isTr ? s.replaceAll('.', ',') : s;

/// Bayt değerini okunur hale getirir: TR "1,25 GB", EN "1.25 GB".
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  String f(double v, int digits) => _dec(v.toStringAsFixed(digits));
  if (bytes >= gb) return '${f(bytes / gb, 2)} GB';
  if (bytes >= mb) return '${f(bytes / mb, bytes >= 10 * mb ? 0 : 1)} MB';
  if (bytes >= kb) return '${f(bytes / kb, 0)} KB';
  return '$bytes B';
}

/// Ondalıklı sayı: TR "2,45", EN "2.45".
String formatDecimal(double v, int digits) => _dec(v.toStringAsFixed(digits));

/// 12345 → TR "12.345", EN "12,345"
String formatCount(int n) {
  final sep = L.isTr ? '.' : ',';
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(sep);
    b.write(s[i]);
  }
  return b.toString();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// TR "22.10.2026", EN "2026-10-22"
String formatDate(DateTime t) =>
    L.isTr ? '${_two(t.day)}.${_two(t.month)}.${t.year}' : '${t.year}-${_two(t.month)}-${_two(t.day)}';

String formatTime(DateTime t) => '${formatDate(t)} ${_two(t.hour)}:${_two(t.minute)}';

/// Yolun son parçasını (dosya veya klasör adını) döndürür.
String baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

/// Ayrı iş parçacığında Türkçe üretilen sabit klasör adlarını çevirir.
String folderLabel(String name) => switch (name) {
      'Bu klasördeki dosyalar' => L.t(name, 'Files in this folder'),
      'Diğer' => L.t(name, 'Other'),
      _ => name,
    };
