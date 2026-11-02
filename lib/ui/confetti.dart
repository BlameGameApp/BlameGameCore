import 'dart:math';

import 'package:flutter/material.dart';

import 'player_cosmetics.dart';

/// One short shower of flat paper in the players' colours, for the winner.
///
/// It falls through and is gone, it can't be tapped, and it isn't drawn at all
/// for anyone who asked the system for reduced motion.
class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();

  // Seeded: every phone in the room gets the same shower.
  late final List<_Paper> _papers = () {
    final random = Random(7);
    return List.generate(70, (i) => _Paper(random, i));
  }();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ConfettiPainter(_controller, _papers),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Paper {
  final Color color;
  final bool round;
  final double start;
  final double x;
  final double size;
  final double sway;
  final double spin;

  _Paper(Random random, int index)
    : color = playerPieces[index % playerPieces.length].fill,
      round = random.nextBool(),
      start = random.nextDouble() * 0.45,
      x = random.nextDouble(),
      size = 7 + random.nextDouble() * 7,
      sway = 10 + random.nextDouble() * 26,
      spin = 3 + random.nextDouble() * 9;
}

class _ConfettiPainter extends CustomPainter {
  final Animation<double> progress;
  final List<_Paper> papers;

  _ConfettiPainter(this.progress, this.papers) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final paper in papers) {
      final t = (progress.value - paper.start) / (1 - paper.start);
      if (t <= 0 || t >= 1) continue;
      final y = -20 + (size.height + 40) * t * t;
      final x = paper.x * size.width + sin(t * pi * 3) * paper.sway;
      paint.color = paper.color;
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(paper.spin * t);
      if (paper.round) {
        canvas.drawCircle(Offset.zero, paper.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: paper.size,
            height: paper.size * 0.6,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => false;
}
