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

  group('PlayerInks', () {
    // Rooms cap at 12, and people are told apart here by their colour.
    test('a full room has no two players on the same colour', () {
      final fills = {for (final p in room) room.inkOf(p.id).fill};
      expect(fills, hasLength(12));
    });

    // Every client seats the room from the same server-ordered list, so the
    // order is the contract, not an implementation detail.
    test('seats follow join order, so all clients agree', () {
      expect(room.inkOf('id-0').fill, playerInks[0].fill);
      expect(room.inkOf('id-1').fill, playerInks[1].fill);
      expect(room.inkOf('id-11').fill, playerInks[11].fill);
    });

    test('someone who left still gets a stable colour', () {
      expect(room.inkOf('gone').fill, room.inkOf('gone').fill);
      expect(room.inkOf(null).fill, isNotNull);
    });

    test("the initial on every player's colour meets WCAG AA", () {
      for (final ink in playerInks) {
        expect(
          _contrast(ink.fill, ink.on),
          greaterThanOrEqualTo(4.5),
          reason: '${ink.on} on ${ink.fill}',
        );
      }
    });
  });
}
