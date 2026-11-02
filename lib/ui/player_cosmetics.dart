import 'package:flutter/material.dart';

import '../models/game_models.dart';

/// A player's flat colour and the text colour that reads on it.
class PlayerInk {
  final Color fill;
  final Color on;

  const PlayerInk(this.fill, this.on);
}

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);

/// One ink per seat: rooms cap at 12 players, so nobody ever shares a colour.
///
/// The order is deliberate. Join order walks down it, and bands stack in join
/// order, so light and dark alternate and two neighbours never blur together.
const List<PlayerInk> playerInks = [
  PlayerInk(Color(0xFFFFC200), _black), // marigold
  PlayerInk(Color(0xFFEE3A1C), _black), // vermilion
  PlayerInk(Color(0xFF1B3BD4), _white), // cobalt
  PlayerInk(Color(0xFFFFB0C8), _black), // blush
  PlayerInk(Color(0xFF0C5E48), _white), // forest
  PlayerInk(Color(0xFFC8E72E), _black), // lime
  PlayerInk(Color(0xFF5A1A6B), _white), // plum
  PlayerInk(Color(0xFF86D2F2), _black), // sky
  PlayerInk(Color(0xFFFF7A14), _black), // tangerine
  PlayerInk(Color(0xFF152A5C), _white), // navy
  PlayerInk(Color(0xFF3FDDB0), _black), // mint
  PlayerInk(Color(0xFFB8A1F7), _black), // lilac
];

/// Per-player colour.
///
/// The server never sends these. They're derived client-side so every client
/// shows the same person the same way, and kept in the UI layer (rather than on
/// [GamePlayer]) so the model stays pure Dart and can be decoded and tested
/// without Flutter.
///
/// The seat comes from the room's join order, which the server fixes for every
/// client, because a colour hashed from the id alone collides: seven players
/// in twelve buckets share one more often than not, and people are told apart
/// here by their colour.
extension PlayerInks on List<GamePlayer> {
  PlayerInk inkOf(String? id) {
    final seat = indexWhere((p) => p.id == id);
    return playerInks[seat >= 0 ? seat % playerInks.length : _slot(id ?? '')];
  }
}

/// Deterministic fallback for an id no longer in the room, such as the owner of
/// a photo who left mid-game.
///
/// Deliberately not `String.hashCode`: Dart only guarantees that to be
/// consistent within a single process, so the VM and dart2js disagree and an
/// iOS player and a web player would see different colours for the same person.
int _slot(String id) =>
    id.codeUnits.fold(0, (hash, unit) => (hash * 31 + unit) % 1000003) %
    playerInks.length;
