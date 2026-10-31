import 'package:flutter/material.dart';

/// OA Labs işareti: amber A'nın içinden geçen O.
class OALabsMark extends StatelessWidget {
  const OALabsMark({super.key, this.size = 30, this.ring = const Color(0xFFEEEAE2), this.legs = const Color(0xFFF2A541)});
  final double size;
  final Color ring;
  final Color legs;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: OALabsMarkPainter(ring: ring, legs: legs)),
    );
  }
}

/// OA Labs işaretini (A'nın içinden geçen O) çizer. 100 birimlik kutuda: A bacakları
/// (26,86)–(52,14)–(78,86), O merkezi (52,58) yarıçap 28; yatayda 2 birim sola kaydırılır.
class OALabsMarkPainter extends CustomPainter {
  OALabsMarkPainter({required this.ring, required this.legs});
  final Color ring;
  final Color legs;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * s) / 2 - 2 * s, (size.height - 100 * s) / 2);
    final w = (size.shortestSide < 24 ? 12.0 : 10.0) * s;
    final legPaint = Paint()
      ..color = legs
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(26 * s, 86 * s)
      ..lineTo(52 * s, 14 * s)
      ..lineTo(78 * s, 86 * s);
    canvas.drawPath(path, legPaint);
    canvas.drawCircle(
      Offset(52 * s, 58 * s),
      28 * s,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(OALabsMarkPainter old) => old.ring != ring || old.legs != legs;
}
