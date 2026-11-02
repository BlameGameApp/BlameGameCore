import 'package:flutter/material.dart';

import 'player_cosmetics.dart';

/// A player's colour with their initial on it, so the same person is easy to
/// spot from screen to screen, and nobody depends on telling two colours apart.
class PlayerAvatar extends StatelessWidget {
  final String name;
  final PlayerInk ink;
  final double radius;

  const PlayerAvatar({
    super.key,
    required this.name,
    required this.ink,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    // Runes, not `name[0]`: an emoji name would otherwise split in half.
    final initial = name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: ink.fill,
        child: Text(
          initial,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: ink.on,
            fontSize: radius * 0.9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
