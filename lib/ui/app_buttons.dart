import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A minimum, not a fixed height: at a large text size a long label wraps and
/// the button grows with it instead of cutting the label off.
const _buttonSize = Size(double.infinity, 56);
const _buttonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

final _shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

/// The screen's main action. Every screen has at most one.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// Shown instead of the label while an action is in flight.
  final bool busy;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: _buttonSize,
        padding: _buttonPadding,
        backgroundColor: colors.brand,
        foregroundColor: colors.ink,
        // Disabled is a status here, not a dead end: the label says what the
        // room is waiting for, so it has to stay comfortably readable.
        disabledBackgroundColor: colors.surface,
        disabledForegroundColor: colors.muted,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: _shape,
      ),
      child: busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.muted,
              ),
            )
          : Text(label, textAlign: TextAlign.center),
    );
  }
}

/// An action that's available but isn't what most players want next.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// Shown instead of the label while an action is in flight.
  final bool busy;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: _buttonSize,
        padding: _buttonPadding,
        backgroundColor: colors.surface,
        foregroundColor: colors.ink,
        disabledBackgroundColor: colors.surface,
        disabledForegroundColor: colors.muted,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: _shape,
      ),
      child: busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.muted,
              ),
            )
          : Text(label, textAlign: TextAlign.center),
    );
  }
}
