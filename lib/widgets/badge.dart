import 'package:flutter/material.dart';

/// Tick in a circle. red = administration, green = guild (in office),
/// blue = verified tutor (earned). Tap to learn what it means.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge(this.color, {super.key, this.size = 16});
  final String? color;
  final double size;

  static Color? _c(String? c) => switch (c) {
        'red' => const Color(0xFFE53935),
        'green' => const Color(0xFF2E9E5B),
        'blue' => const Color(0xFF1E88E5),
        _ => null,
      };

  static String meaning(String? c) => switch (c) {
        'red' => 'Red tick: official University Administration.',
        'green' => 'Green tick: a Guild member who holds this office right now. It goes away when their term ends.',
        'blue' => 'Blue tick: tutor verified by many real reviews. It is earned, not given.',
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
          builder: (_) => AlertDialog(
            content: Text(meaning(color)),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        ),
        child: Container(
          width: size,
          height: size,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(color: col, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, color: Colors.white, size: size * 0.72),
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
