import 'package:flutter/material.dart';

import '../models/game_models.dart';

/// A player's board-game piece: a colour, a shape, and the text colour that
/// reads on it. Shape and colour together, so two people are told apart by more
/// than a shade.
class PlayerPiece {
  final Color fill;
  final Color on;
  final ShapeBorder shape;

  /// How far the shape sits off square, in radians. Pieces look put down by
  /// hand, not stamped out by a grid.
  final double tilt;

  const PlayerPiece(this.fill, this.on, this.shape, {this.tilt = 0});
}

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);

/// One piece per seat: rooms cap at 12 players, so nobody ever shares one.
const List<PlayerPiece> playerPieces = [
  PlayerPiece(Color(0xFFFFC200), _black, CircleBorder()), // marigold
  PlayerPiece(
    Color(0xFFEE3A1C),
    _black,
    StarBorder.polygon(sides: 6, pointRounding: 0.3),
    tilt: 0.12,
  ), // vermilion
  PlayerPiece(
    Color(0xFF1B3BD4),
    _white,
    StarBorder.polygon(sides: 4, rotation: 45, pointRounding: 0.4),
    tilt: -0.14,
  ), // cobalt
  PlayerPiece(
    Color(0xFFFFB0C8),
    _black,
    StarBorder(points: 8, innerRadiusRatio: 0.8, pointRounding: 0.6),
  ), // blush
  PlayerPiece(
    Color(0xFF0C5E48),
    _white,
    StarBorder.polygon(sides: 5, pointRounding: 0.3),
    tilt: 0.1,
  ), // forest
  PlayerPiece(
    Color(0xFFC8E72E),
    _black,
    StarBorder(points: 5, innerRadiusRatio: 0.64, pointRounding: 0.5),
    tilt: -0.1,
  ), // lime
  PlayerPiece(
    Color(0xFF5A1A6B),
    _white,
    StarBorder.polygon(sides: 4, pointRounding: 0.3),
  ), // plum
  PlayerPiece(
    Color(0xFF86D2F2),
    _black,
    StarBorder(points: 12, innerRadiusRatio: 0.86, pointRounding: 0.4),
  ), // sky
  PlayerPiece(
    Color(0xFFFF7A14),
    _black,
    StarBorder.polygon(sides: 8, pointRounding: 0.2),
    tilt: 0.2,
  ), // tangerine
  PlayerPiece(
    Color(0xFF152A5C),
    _white,
    StarBorder(points: 4, innerRadiusRatio: 0.66, pointRounding: 0.8),
    tilt: 0.3,
  ), // navy
  PlayerPiece(
    Color(0xFF3FDDB0),
    _black,
    StarBorder(points: 6, innerRadiusRatio: 0.72, pointRounding: 0.7),
  ), // mint
  PlayerPiece(
    Color(0xFFB8A1F7),
    _black,
    StarBorder(points: 3, innerRadiusRatio: 0.72, pointRounding: 0.9),
    tilt: 0.14,
  ), // lilac
];

/// Per-player piece.
///
/// The server never sends these. They're derived client-side so every client
/// shows the same person the same way, and kept in the UI layer (rather than on
/// [GamePlayer]) so the model stays pure Dart and can be decoded and tested
/// without Flutter.
///
/// The seat comes from the room's join order, which the server fixes for every
/// client, because a piece hashed from the id alone collides: seven players
/// in twelve buckets share one more often than not.
extension PlayerPieces on List<GamePlayer> {
  PlayerPiece pieceOf(String? id) {
    final seat = indexWhere((p) => p.id == id);
    return playerPieces[seat >= 0
        ? seat % playerPieces.length
        : _slot(id ?? '')];
  }
}

/// Deterministic fallback for an id no longer in the room, such as a player who
/// left before the final rankings.
///
/// Deliberately not `String.hashCode`: Dart only guarantees that to be
/// consistent within a single process, so the VM and dart2js disagree and an
/// iOS player and a web player would see different colours for the same person.
int _slot(String id) =>
    id.codeUnits.fold(0, (hash, unit) => (hash * 31 + unit) % 1000003) %
    playerPieces.length;
