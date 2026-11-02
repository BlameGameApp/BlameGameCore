import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_blame/models/game_models.dart';
import 'package:photo_blame/ui/player_cosmetics.dart';

double _contrast(Color a, Color b) {
  final (hi, lo) = (
    max(a.computeLuminance(), b.computeLuminance()),
    min(a.computeLuminance(), b.computeLuminance()),
  );
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final room = [
    for (var i = 0; i < 12; i++) GamePlayer(id: 'id-$i', name: 'Player $i'),
  ];

  group('PlayerPieces', () {
    // Rooms cap at 12, and each player is theirs for the whole game.
    test('a full room has no two players on the same colour', () {
      final fills = {for (final p in room) room.pieceOf(p.id).fill};
      expect(fills, hasLength(12));
    });

    test('a full room has no two players on the same shape', () {
      final shapes = {for (final p in room) room.pieceOf(p.id).shape};
      expect(shapes, hasLength(12));
    });

    // Every client seats the room from the same server-ordered list, so the
    // order is the contract, not an implementation detail.
    test('seats follow join order, so all clients agree', () {
      expect(room.pieceOf('id-0').fill, playerPieces[0].fill);
      expect(room.pieceOf('id-1').fill, playerPieces[1].fill);
      expect(room.pieceOf('id-11').fill, playerPieces[11].fill);
    });

    test('someone who left still gets a stable colour', () {
      expect(room.pieceOf('gone').fill, room.pieceOf('gone').fill);
      expect(room.pieceOf(null).fill, isNotNull);
    });

    test("the initial on every player's piece meets WCAG AA", () {
      for (final piece in playerPieces) {
        expect(
          _contrast(piece.fill, piece.on),
          greaterThanOrEqualTo(4.5),
          reason: '${piece.on} on ${piece.fill}',
        );
      }
    });
  });
}
