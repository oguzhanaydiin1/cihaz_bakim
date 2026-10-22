/// Bayt değerini Türkçe biçimde okunur hale getirir: 1,25 GB, 340 MB, 4,2 MB.
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  String f(double v, int digits) => v.toStringAsFixed(digits).replaceAll('.', ',');
  if (bytes >= gb) return '${f(bytes / gb, 2)} GB';
  if (bytes >= mb) return '${f(bytes / mb, bytes >= 10 * mb ? 0 : 1)} MB';
  if (bytes >= kb) return '${f(bytes / kb, 0)} KB';
  return '$bytes B';
}

/// 12345 → "12.345"
String formatCount(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

String formatTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
}

/// Yolun son parçasını (dosya veya klasör adını) döndürür.
String baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}
