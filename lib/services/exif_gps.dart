import 'dart:convert';
import 'dart:typed_data';

// JPEG dosyalarındaki konum (GPS) bilgisini okur ve KAYIPSIZ siler.
// Fotoğrafın görüntü verisine hiç dokunulmaz, yeniden sıkıştırma yapılmaz;
// yalnızca EXIF'teki GPS bölümü sıfırlanır ve konum içeren XMP bölümü çıkarılır.
// Fotoğrafın yönü, çekim tarihi gibi diğer bilgiler korunur.

class GpsReading {
  const GpsReading({this.latitude, this.longitude});
  final double? latitude;
  final double? longitude;
}

class _Segment {
  _Segment(this.marker, this.start, this.end);
  final int marker;

  /// 0xFF baytının konumu.
  final int start;

  /// Bölümün bittiği yer (hariç).
  final int end;
}

const _exifHeader = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"
const _xmpHeader = 'http://ns.adobe.com/xap/1.0/';

bool isJpeg(Uint8List b) => b.length > 4 && b[0] == 0xFF && b[1] == 0xD8;

/// Görüntü verisi (SOS) başlayana kadarki bölümleri listeler.
List<_Segment> _segments(Uint8List b) {
  final result = <_Segment>[];
  if (!isJpeg(b)) return result;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) break;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // dolgu baytı
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) break; // görüntü verisi veya dosya sonu
    if ((marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2 || i + 2 + len > b.length) break;
    result.add(_Segment(marker, i, i + 2 + len));
    i += 2 + len;
  }
  return result;
}

bool _startsWith(Uint8List b, int offset, List<int> prefix) {
  if (offset + prefix.length > b.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (b[offset + i] != prefix[i]) return false;
  }
  return true;
}

bool _isExif(Uint8List b, _Segment s) => s.marker == 0xE1 && _startsWith(b, s.start + 4, _exifHeader);

bool _isXmpWithGps(Uint8List b, _Segment s) {
  if (s.marker != 0xE1 || !_startsWith(b, s.start + 4, ascii.encode(_xmpHeader))) return false;
  final text = latin1.decode(b.sublist(s.start + 4, s.end), allowInvalid: true);
  return text.contains('GPSLatitude') || text.contains('GPSLongitude');
}

/// EXIF içindeki TIFF yapısını sınır kontrolüyle okur/yazar.
class _Tiff {
  _Tiff(this.b, this.base, this.limit) : little = b[base] == 0x49;

  final Uint8List b;

  /// TIFF başlığının dosyadaki konumu; tüm ofsetler buna göredir.
  final int base;

  /// EXIF bölümünün sonu: bunun ötesine okunmaz/yazılmaz.
  final int limit;
  final bool little;

  int _abs(int off, int size) {
    final a = base + off;
    if (off < 0 || a + size > limit) throw RangeError('EXIF dışı ofset');
    return a;
  }

  int u16(int off) {
    final a = _abs(off, 2);
    return little ? b[a] | (b[a + 1] << 8) : (b[a] << 8) | b[a + 1];
  }

  int u32(int off) {
    final a = _abs(off, 4);
    return little
        ? b[a] | (b[a + 1] << 8) | (b[a + 2] << 16) | (b[a + 3] << 24)
        : (b[a] << 24) | (b[a + 1] << 16) | (b[a + 2] << 8) | b[a + 3];
  }

  void w16(int off, int v) {
    final a = _abs(off, 2);
    if (little) {
      b[a] = v & 0xFF;
      b[a + 1] = (v >> 8) & 0xFF;
    } else {
      b[a] = (v >> 8) & 0xFF;
      b[a + 1] = v & 0xFF;
    }
  }

  void zero(int off, int size) {
    final a = _abs(off, size);
    b.fillRange(a, a + size, 0);
  }

  /// IFD içindeki bir etiketin girdi konumu.
  int? findEntry(int ifd, int tag) {
    final n = u16(ifd);
    for (var i = 0; i < n; i++) {
      final e = ifd + 2 + i * 12;
      if (u16(e) == tag) return e;
    }
    return null;
  }

  /// GPS bölümünün ofseti (yoksa null).
  int? gpsIfd() {
    if (!(b[base] == 0x49 && b[base + 1] == 0x49) && !(b[base] == 0x4D && b[base + 1] == 0x4D)) return null;
    final ifd0 = u32(4);
    final e = findEntry(ifd0, 0x8825);
    if (e == null) return null;
    final off = u32(e + 8);
    return off == 0 ? null : off;
  }
}

int _typeSize(int type) {
  switch (type) {
    case 1:
    case 2:
    case 6:
    case 7:
      return 1;
    case 3:
    case 8:
      return 2;
    case 4:
    case 9:
    case 11:
      return 4;
    case 5:
    case 10:
    case 12:
      return 8;
    default:
      return 0;
  }
}

/// Fotoğraftaki konumu okur. Konum yoksa null döner.
GpsReading? readGps(Uint8List b) {
  try {
    var foundInXmp = false;
    for (final s in _segments(b)) {
      if (_isXmpWithGps(b, s)) foundInXmp = true;
      if (!_isExif(b, s)) continue;
      final t = _Tiff(b, s.start + 10, s.end);
      final gps = t.gpsIfd();
      if (gps == null) continue;
      final n = t.u16(gps);
      if (n == 0) continue;

      String? latRef;
      String? lonRef;
      double? lat;
      double? lon;
      double dms(int entry) {
        final count = t.u32(entry + 4);
        if (count < 3) throw RangeError('GPS');
        final off = t.u32(entry + 8);
        double r(int i) {
          final den = t.u32(off + i * 8 + 4);
          return den == 0 ? 0 : t.u32(off + i * 8) / den;
        }

        return r(0) + r(1) / 60 + r(2) / 3600;
      }

      for (var i = 0; i < n; i++) {
        final e = gps + 2 + i * 12;
        switch (t.u16(e)) {
          case 1:
            latRef = String.fromCharCode(b[t.base + e + 8]);
          case 2:
            lat = dms(e);
          case 3:
            lonRef = String.fromCharCode(b[t.base + e + 8]);
          case 4:
            lon = dms(e);
        }
      }
      final la = lat;
      final lo = lon;
      if (la == null || lo == null || (la == 0 && lo == 0)) return const GpsReading();
      return GpsReading(
        latitude: latRef == 'S' ? -la : la,
        longitude: lonRef == 'W' ? -lo : lo,
      );
    }
    return foundInXmp ? const GpsReading() : null;
  } catch (_) {
    return null; // bozuk veya alışılmadık EXIF: dokunma
  }
}

/// Konum bilgisi silinmiş yeni dosya içeriğini döndürür. Konum yoksa null.
Uint8List? stripGps(Uint8List source) {
  final b = Uint8List.fromList(source);
  var changed = false;
  final segs = _segments(b);

  for (final s in segs) {
    if (!_isExif(b, s)) continue;
    try {
      final t = _Tiff(b, s.start + 10, s.end);
      final gps = t.gpsIfd();
      if (gps == null) continue;
      final n = t.u16(gps);
      if (n == 0) continue;
      for (var i = 0; i < n; i++) {
        final e = gps + 2 + i * 12;
        final size = _typeSize(t.u16(e + 2)) * t.u32(e + 4);
        if (size > 4) {
          final off = t.u32(e + 8);
          try {
            t.zero(off, size); // değerin kendisi (koordinatlar)
          } catch (_) {}
        }
      }
      t.zero(gps + 2, n * 12 + 4); // girdiler ve sonraki IFD bağlantısı
      t.w16(gps, 0); // boş GPS bölümü: geçerli bir yapı olarak kalır
      changed = true;
    } catch (_) {
      // Bu bölüm okunamadı; dosyayı bozmamak için dokunma.
    }
  }

  // Konum içeren XMP bölümlerini tamamen çıkar.
  final xmp = segs.where((s) => _isXmpWithGps(source, s)).toList();
  if (xmp.isEmpty) return changed ? b : null;

  final out = BytesBuilder(copy: false);
  var pos = 0;
  for (final s in xmp) {
    out.add(Uint8List.sublistView(b, pos, s.start));
    pos = s.end;
  }
  out.add(Uint8List.sublistView(b, pos));
  return out.toBytes();
}
