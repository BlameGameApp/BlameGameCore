import 'package:flutter/material.dart';

import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import 'band.dart';
import 'error_text.dart';
import 'snack.dart';

/// Shown when the live connection has dropped.
///
/// Events that fired while disconnected are gone, so reconnecting re-seeds
/// from the server snapshot. Without this a dropped socket leaves the player
/// staring at a frozen screen with no explanation and no way back in.
///
/// Sits under a screen's top band, which is what clears the status bar.
class ConnectionBanner extends StatefulWidget {
  final GameController controller;

  const ConnectionBanner({super.key, required this.controller});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await widget.controller.reconnect();
    } on Exception catch (e) {
      if (!mounted) return;
      showSnack(context, 'Still offline: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.connectionError == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    // An automatic retry is already queued, so offering Retry would just be a
    // button that duplicates work already under way.
    final busy = _retrying || widget.controller.isReconnecting;
    final text = uiText(16, weight: 700, color: colors.ink);
    return Band(
      color: colors.vermilion,
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: Text(busy ? 'Reconnecting…' : 'Connection lost', style: text),
          ),
          if (busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colors.ink,
              ),
            )
          else
            TextButton(
              onPressed: _retry,
              child: Text('Retry', style: text),
            ),
        ],
      ),
    );
  }
}
