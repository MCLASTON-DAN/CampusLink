import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tick in a circle. red = administration, green = guild (in office),
/// purple = Campus Newsroom, blue = verified tutor (earned). Tap to learn what it means.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge(this.color, {super.key, this.size = 16});
  final String? color;
  final double size;

  static Color? _c(String? c) => switch (c) {
        'red' => const Color(0xFFE0245E),
        'green' => const Color(0xFF14A44D),
        'blue' => const Color(0xFF0095F6),
        'purple' => const Color(0xFF7C3AED),
        'orange' => const Color(0xFFF2780C),
        _ => null,
      };

  static String meaning(String? c) => switch (c) {
        'red' => 'Red tick: official University Administration.',
        'green' => 'Green tick: a Guild member who holds this office right now. It goes away when their term ends.',
        'blue' => 'Blue tick: tutor verified by many real reviews. It is earned, not given.',
        'purple' => 'Purple tick: a member of the Campus Newsroom (at most 5 people), while in post.',
        'orange' => 'Orange tick: a lecturer, assigned by the university to the units they teach.',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final col = _c(color);
    if (col == null) return const SizedBox.shrink();
    return Tooltip(
      message: meaning(color),
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: Text(meaning(color)),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK'))],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: SizedBox.square(dimension: size, child: CustomPaint(painter: _RosettePainter(col))),
        ),
      ),
    );
  }
}

/// "Name ✓" on one line.
class NameWithBadge extends StatelessWidget {
  const NameWithBadge(this.name, this.badge, {super.key, this.style});
  final String name;
  final String? badge;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(name, style: style, overflow: TextOverflow.ellipsis)),
          VerifiedBadge(badge),
        ],
      );
}


/// The verified "rosette": a circle with soft scalloped edges and a white
/// tick, in the style people know from verified accounts.
class _RosettePainter extends CustomPainter {
  _RosettePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    const bumps = 12;
    final path = Path();
    const steps = 144;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * 2 * math.pi;
      // Radius wobbles gently 12 times around the circle.
      final rr = r * (0.92 + 0.08 * math.cos(bumps * t));
      final p = c + Offset(math.cos(t), math.sin(t)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    final hsl = HSLColor.fromColor(color);
    final light = hsl.withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0)).toColor();
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, color])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final tick = Path()
      ..moveTo(c.dx - r * 0.38, c.dy + r * 0.02)
      ..lineTo(c.dx - r * 0.1, c.dy + r * 0.3)
      ..lineTo(c.dx + r * 0.4, c.dy - r * 0.28);
    canvas.drawPath(
      tick,
      Paint()
        ..isAntiAlias = true
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_RosettePainter old) => old.color != color;
}
