// Regression tests for TASK-46.
//
// `Navigator.pushReplacement` completes the route it replaces *before* the new
// route is mounted, so a `await Navigator.push(...)` one level up resolves in
// the middle of a lobby -> game hand-off. Whoever owns the controller must not
// tear it down on that completion, or the incoming screen calls `addListener`
// on an already-disposed notifier.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_blame/models/game_models.dart';
import 'package:photo_blame/screens/lobby_screen.dart';
import 'package:photo_blame/state/game_controller.dart';
import 'package:photo_blame/theme/app_theme.dart';

import 'support/pump.dart';

/// Stands in for `HomeScreen._run`: pushes the lobby, awaits it, and disposes
/// the controller it created when that push resolves.
class _OwnerScreen extends StatefulWidget {
  final GameController controller;

  const _OwnerScreen({required this.controller});

  @override
  State<_OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends State<_OwnerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LobbyScreen(controller: widget.controller),
              ),
            );
            widget.controller.dispose();
          },
          child: const Text('GO'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
      'starting a game does not dispose the controller the game screen needs',
      (tester) async {
    final h = await harness();

    tester.view.physicalSize = phoneSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: _OwnerScreen(controller: h.controller),
      ),
    );

    // Home -> Lobby.
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();
    expect(find.text('Game code'), findsOneWidget);

    // The backend starts the game: the lobby pushReplacement's the game screen,
    // which completes the lobby route and resolves the owner's `await push`.
    h.socket.emit(
      RoundStarted(
        roundIndex: 0,
        photo: const PhotoInfo(id: 'ph1', ownerId: 'p2', url: '/photo.jpg'),
        roundEndsAt: DateTime.now().millisecondsSinceEpoch + 10000,
      ),
    );
    await tester.pumpAndSettle();

    // Without the fix this throws "A GameController was used after being
    // disposed" from _GameScreenState.initState.
    expect(tester.takeException(), isNull);
    // dispose() closes the socket, so an open socket means the controller is
    // still alive for the game screen that is now listening to it.
    expect(h.socket.closed, isFalse);
    expect(find.text('Game code'), findsNothing);
  });

  testWidgets('the controller is still disposed once the flow really unwinds',
      (tester) async {
    final h = await harness();

    tester.view.physicalSize = phoneSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: _OwnerScreen(controller: h.controller),
      ),
    );

    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();

    // Back out of the lobby: this is a real unwind, so teardown must happen.
    final lobbyContext = tester.element(find.byType(LobbyScreen));
    Navigator.of(lobbyContext).pop();
    await tester.pumpAndSettle();

    expect(h.socket.closed, isTrue);
  });
}
