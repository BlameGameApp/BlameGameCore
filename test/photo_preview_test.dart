import 'dart:typed_data';

import 'package:photo_blame/screens/lobby_screen.dart';
import 'package:photo_blame/services/photo_sampler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';

/// A 1x1 PNG — [Image.memory] needs bytes a real decoder accepts.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Hands out canned batches instead of touching the camera roll, and records
/// the exclude sets it was asked for.
class FakeSampler implements PhotoSampler {
  final List<List<String>> batches;
  final List<Set<String>> excludes = [];
  int calls = 0;

  FakeSampler(this.batches);

  @override
  Future<List<SampledPhoto>> sampleRandomPhotos({
    required int count,
    Set<String> exclude = const {},
  }) async {
    // Copy: the sheet passes its live "already seen" set, which keeps growing.
    excludes.add({...exclude});
    final ids = calls < batches.length ? batches[calls] : <String>[];
    calls++;
    return [
      for (final id in ids)
        SampledPhoto(id: id, thumbnail: _png, bytes: Uint8List.fromList([1])),
    ];
  }
}

/// The ADD PHOTOS button shows an infinite spinner while the preview is open,
/// so `pumpAndSettle` never returns — pump a fixed number of frames instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openPreview(WidgetTester tester, FakeSampler sampler) async {
  final h = await harness();
  await pumpScreen(
    tester,
    LobbyScreen(controller: h.controller, sampler: sampler),
  );
  await tester.tap(find.text('Add photos'));
  await settle(tester);
}

/// The default harness snapshot, but for a hardcore room.
const _hardcoreSnapshot = {
  'state': 'lobby',
  'round_seconds': 10,
  'hardcore': true,
  'players': [
    {'id': 'me', 'name': 'Emma', 'is_host': true, 'score': 0},
    {'id': 'p2', 'name': 'Jake', 'is_host': false, 'score': 0},
  ],
};

void main() {
  testWidgets('previews the sampled photos before anything is uploaded',
      (tester) async {
    final sampler = FakeSampler([
      ['a', 'b', 'c'],
    ]);
    await _openPreview(tester, sampler);

    expect(find.text('These photos?'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(3));
    expect(find.text('Use these'), findsOneWidget);
    expect(find.text('Reshuffle'), findsOneWidget);
  });

  testWidgets('reshuffle asks for a fresh batch, excluding what was shown',
      (tester) async {
    final sampler = FakeSampler([
      ['a', 'b'],
      ['c', 'd'],
    ]);
    await _openPreview(tester, sampler);

    await tester.tap(find.text('Reshuffle'));
    await settle(tester);

    expect(sampler.calls, 2);
    expect(sampler.excludes.first, isEmpty);
    expect(sampler.excludes.last, {'a', 'b'});
    // Still previewing, still nothing uploaded.
    expect(find.text('These photos?'), findsOneWidget);
  });

  testWidgets('a second reshuffle excludes both earlier batches',
      (tester) async {
    final sampler = FakeSampler([
      ['a'],
      ['b'],
      ['c'],
    ]);
    await _openPreview(tester, sampler);

    await tester.tap(find.text('Reshuffle'));
    await settle(tester);
    await tester.tap(find.text('Reshuffle'));
    await settle(tester);

    expect(sampler.excludes.last, {'a', 'b'});
  });

  testWidgets('an empty reshuffle keeps the current photos', (tester) async {
    final sampler = FakeSampler([
      ['a', 'b'],
      <String>[],
    ]);
    await _openPreview(tester, sampler);

    await tester.tap(find.text('Reshuffle'));
    await settle(tester);

    expect(find.text('No other photos to shuffle in'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('confirming uploads the previewed photos', (tester) async {
    final sampler = FakeSampler([
      ['a', 'b'],
    ]);
    final h = await harness();
    await pumpScreen(
      tester,
      LobbyScreen(controller: h.controller, sampler: sampler),
    );
    expect(h.http.countFor('/photos'), 0);

    await tester.tap(find.text('Add photos'));
    await settle(tester);
    await tester.tap(find.text('Use these'));
    await settle(tester);

    expect(h.http.countFor('/photos'), 2);
  });

  testWidgets('hardcore mode uploads blind, with no preview or reshuffle',
      (tester) async {
    final sampler = FakeSampler([
      ['a', 'b'],
    ]);
    final h = await harness(snapshot: _hardcoreSnapshot);
    await pumpScreen(
      tester,
      LobbyScreen(controller: h.controller, sampler: sampler),
    );

    await tester.tap(find.text('Add photos'));
    await settle(tester);

    expect(find.text('These photos?'), findsNothing);
    expect(find.text('Reshuffle'), findsNothing);
    // Straight to the server, no confirmation step.
    expect(h.http.countFor('/photos'), 2);
  });

  testWidgets('the lobby states the mode before anything is uploaded',
      (tester) async {
    final normal = await harness();
    await pumpScreen(tester, LobbyScreen(controller: normal.controller));
    expect(find.textContaining('reshuffle before sharing'), findsOneWidget);
    expect(normal.http.countFor('/photos'), 0);

    final hard = await harness(snapshot: _hardcoreSnapshot);
    await pumpScreen(tester, LobbyScreen(controller: hard.controller));
    expect(find.textContaining('Hardcore:'), findsOneWidget);
    expect(
      find.textContaining('without showing them to you first'),
      findsOneWidget,
    );
    expect(hard.http.countFor('/photos'), 0);
  });

  testWidgets('a client that has not learned the mode cannot sample',
      (tester) async {
    final sampler = FakeSampler([
      ['a', 'b'],
    ]);
    final h = await harness();
    // Simulate a client whose snapshot has not landed yet.
    h.controller.hardcore = null;
    await pumpScreen(
      tester,
      LobbyScreen(controller: h.controller, sampler: sampler),
    );

    await tester.tap(find.text('Add photos'));
    await settle(tester);

    // Nothing was even read off the camera roll, let alone uploaded.
    expect(sampler.calls, 0);
    expect(h.http.countFor('/photos'), 0);
  });

  testWidgets('dismissing the preview uploads nothing', (tester) async {
    final sampler = FakeSampler([
      ['a', 'b'],
    ]);
    final h = await harness();
    await pumpScreen(
      tester,
      LobbyScreen(controller: h.controller, sampler: sampler),
    );

    await tester.tap(find.text('Add photos'));
    await settle(tester);
    Navigator.of(tester.element(find.text('These photos?'))).pop();
    await settle(tester);

    expect(h.http.countFor('/photos'), 0);
  });
}
