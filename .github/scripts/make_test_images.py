"""Emülatör testi için fotoğraflar: hc_a.jpg ve hc_b.jpg (aynı, İstanbul konumlu), hc_big.jpg (büyük)."""
import io
import os
import sys

import piexif
from PIL import Image

out = sys.argv[1]
os.makedirs(out, exist_ok=True)


def rat(v):
    return (int(round(v * 10000)), 10000)


img = Image.new('RGB', (800, 600), (200, 80, 40))
exif = {
    '0th': {piexif.ImageIFD.Make: b'HarrierTest'},
    'GPS': {
        piexif.GPSIFD.GPSLatitudeRef: b'N',
        piexif.GPSIFD.GPSLatitude: [(41, 1), (0, 1), rat(54.36)],
        piexif.GPSIFD.GPSLongitudeRef: b'E',
        piexif.GPSIFD.GPSLongitude: [(28, 1), (58, 1), rat(46.2)],
    },
}
buf = io.BytesIO()
img.save(buf, 'jpeg', quality=95, exif=piexif.dump(exif))
for name in ('hc_a.jpg', 'hc_b.jpg'):
    with open(os.path.join(out, name), 'wb') as f:
        f.write(buf.getvalue())

# Ayrıntılı (gürültülü) büyük fotoğraf: kalite 100'de birkaç MB, 75'te belirgin küçülür.
# (Düz renk geçişi fazla iyi sıkışır ve 1 MB sınırının altında kalır.)
w, h = 2000, 1500
big = Image.frombytes('RGB', (w, h), os.urandom(w * h * 3))
big.save(os.path.join(out, 'hc_big.jpg'), 'jpeg', quality=100)
for n in os.listdir(out):
    print(n, os.path.getsize(os.path.join(out, n)))
