import 'package:flutter/material.dart';

import '../state/game_controller.dart';
import 'snack.dart';

/// Shared wiring for the screens a [GameController] drives.
///
/// All three of them need the same three things, and each one is a crash if it
/// is left out: the listener has to be removed in `dispose` (it also releases
/// the controller, which defers its own teardown until the last screen lets
/// go), the callback has to check [State.mounted] before touching
/// `Navigator.of(context)` because it fires from the WebSocket stream, and
/// route pushes have to be latched so a burst of events cannot push the same
/// screen twice. TASK-46 was exactly the third one going wrong.
mixin GameControllerScreen<T extends StatefulWidget> on State<T> {
  /// The controller this screen renders.
  GameController get controller;

  bool _navigated = false;

  /// True once this screen has handed off to another route, or been popped.
  bool get navigated => _navigated;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleChange);
  }

  @override
  void dispose() {
    controller.removeListener(_handleChange);
    super.dispose();
  }

  /// Called on every controller change, after the mounted guard.
  ///
  /// Return true when the screen has navigated away, so no `setState` runs on
  /// a route that is already leaving. The default does nothing but rebuild.
  bool onControllerChange() => false;

  void _handleChange() {
    // Guard first: this fires from the WebSocket stream, so the State can be
    // defunct by now and Navigator.of(context) would throw.
    if (!mounted) return;
    if (onControllerChange()) return;
    setState(() {});
  }

  /// Runs [go] the first time only, and records that this screen has left.
  ///
  /// Returns whether it ran, so callers can use it as the "handled" answer
  /// from [onControllerChange].
  bool navigateOnce(void Function() go) {
    if (_navigated) return false;
    _navigated = true;
    go();
    return true;
  }

  /// Goes back to home once this player is out of the room, however that came
  /// about. Screens call this first in [onControllerChange].
  bool leaveIfRemoved() {
    if (!controller.hasLeftRoom) return false;
    return navigateOnce(() {
      final reason = controller.removedFromRoom;
      // Grab the messenger before popping: showing the snackbar on this route
      // and then popping takes the explanation down with the screen, so the
      // player is ejected with no idea why.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      if (reason != null) {
        messenger.showSnackBar(SnackBar(content: Text(reason)));
      }
    });
  }

  /// Shows a transient message, if this screen is still on screen.
  void snack(String message) => showSnack(context, message);
}
