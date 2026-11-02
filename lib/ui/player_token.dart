import 'package:flutter/material.dart';

import 'player_cosmetics.dart';

/// A [PlayerPiece] with a letter on it.
class PlayerToken extends StatelessWidget {
  /// Shown by its first character.
  final String name;
  final PlayerPiece piece;
  final double radius;

  /// Lands with a small bounce on first build, for a player arriving in the
  /// lobby. Respects reduced motion.
  final bool popIn;

  const PlayerToken({
    super.key,
    required this.name,
    required this.piece,
    this.radius = 20,
    this.popIn = false,
  });

  @override
  Widget build(BuildContext context) {
    // Runes, not `name[0]`: a name starting with an accent or a symbol from
    // outside the basic plane would otherwise split in half.
    final initial = name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();
    final token = ExcludeSemantics(
      child: SizedBox.square(
        dimension: radius * 2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Only the shape tilts: a tilted letter is slower to read.
            Positioned.fill(
              child: Transform.rotate(
                angle: piece.tilt,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: piece.fill,
                    shape: piece.shape,
                  ),
                ),
              ),
            ),
            Text(
              initial,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: piece.on,
                fontSize: radius * 0.9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
    if (!popIn || MediaQuery.disableAnimationsOf(context)) return token;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: token,
    );
  }
}
