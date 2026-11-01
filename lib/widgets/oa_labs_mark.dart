import 'dart:math' as math;

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

/// OA Labs mühürü: iki halka, aralarında dönen "OA LABS · ATÖLYE · 2026" yazısı, ortada A.
/// Yazı 40 saniyede bir tur döner; sistemde hareketi azaltma açıksa durur.
class OALabsSeal extends StatefulWidget {
  const OALabsSeal({
    super.key,
    this.size = 96,
    required this.color,
    required this.accent,
    this.text = 'OA LABS · ATÖLYE · 2026 · OA LABS · ATÖLYE · 2026 · ',
  });
  final double size;
  final Color color;
  final Color accent;
  final String text;

  @override
  State<OALabsSeal> createState() => _OALabsSealState();
}

class _OALabsSealState extends State<OALabsSeal> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 40));
  List<TextPainter> _glyphs = const [];

  void _layoutGlyphs() {
    _glyphs = widget.text
        .split('')
        .map((ch) => TextPainter(
              text: TextSpan(
                text: ch,
                style: TextStyle(color: widget.color, fontSize: 11, fontWeight: FontWeight.w600, height: 1),
              ),
              textDirection: TextDirection.ltr,
            )..layout())
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _layoutGlyphs();
  }

  @override
  void didUpdateWidget(OALabsSeal old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.color != widget.color) _layoutGlyphs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'OA Labs',
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _turn,
          builder: (context, _) => CustomPaint(
            painter: _OALabsSealPainter(
              color: widget.color,
              accent: widget.accent,
              glyphs: _glyphs,
              turn: _turn.value * 2 * math.pi,
            ),
          ),
        ),
      ),
    );
  }
}

class _OALabsSealPainter extends CustomPainter {
  _OALabsSealPainter({required this.color, required this.accent, required this.glyphs, required this.turn});
  final Color color;
  final Color accent;
  final List<TextPainter> glyphs;
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    // Çizim 140 birimlik kutuda, merkez (0,0).
    final s = size.shortestSide / 140;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(Offset.zero, 64, ring);
    canvas.drawCircle(Offset.zero, 42, ring);
    if (glyphs.isNotEmpty) {
      final step = 2 * math.pi / glyphs.length;
      for (var i = 0; i < glyphs.length; i++) {
        final g = glyphs[i];
        canvas.save();
        canvas.rotate(turn + i * step);
        canvas.translate(0, -53);
        g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
        canvas.restore();
      }
    }
    final a = Path()
      ..moveTo(-15, 18)
      ..lineTo(0, -20)
      ..lineTo(15, 18);
    canvas.drawPath(
      a,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OALabsSealPainter old) =>
      old.turn != turn || old.color != color || old.accent != accent || old.glyphs != glyphs;
}
