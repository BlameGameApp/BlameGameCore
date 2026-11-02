import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'fit_text.dart';
import 'player_cosmetics.dart';

/// Horizontal margin inside every band.
const double bandGutter = 16;

/// Every screen is a stack of full-width bands that bleed to the screen edges,
/// so each one paints behind the status bar and the home indicator itself.
/// [top] is the band under the status bar: it picks the status bar's text
/// colour, and a white clock on a marigold band is unreadable.
class PosterScaffold extends StatelessWidget {
  final Color top;
  final Widget body;

  /// What's behind the stack. iOS tints the keyboard from it, so a screen with
  /// text fields needs a neutral one here. Defaults to [top].
  final Color? background;

  /// Off where nothing on the screen takes text: the keyboard from the previous
  /// route is still animating out when a screen appears, and squeezing a full
  /// stack of bands for those few frames overflows it.
  final bool resizeForKeyboard;

  const PosterScaffold({
    super.key,
    required this.top,
    required this.body,
    this.background,
    this.resizeForKeyboard = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: top.computeLuminance() > 0.15
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: background ?? top,
        resizeToAvoidBottomInset: resizeForKeyboard,
        body: body,
      ),
    );
  }
}

/// A full-width block of flat colour.
///
/// The fill is painted by a [Material] rather than a `BoxDecoration`, because
/// bands contain tappable things. Ink highlights are drawn on the nearest
/// [Material] ancestor, so a decorated box painted *over* that ancestor
/// swallows them, and Flutter asserts on exactly this arrangement.
class Band extends StatelessWidget {
  final Color color;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? height;

  const Band({
    super.key,
    required this.color,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: bandGutter),
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: color,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A band you can press. The label is left aligned on the band's gutter, so
/// a screen's actions line up with the names above them.
class BandButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;

  /// Shows a spinner at the far end while an action is in flight.
  final bool busy;

  /// Set on the last band of a screen: the band runs on under the home
  /// indicator with its label above it.
  final bool last;

  final double height;

  const BandButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.color,
    required this.textColor,
    this.busy = false,
    this.last = false,
    this.height = 68,
  });

  @override
  Widget build(BuildContext context) {
    final inset = last ? MediaQuery.paddingOf(context).bottom : 0.0;
    final enabled = onPressed != null;
    final text = enabled ? textColor : context.colors.paperMuted;
    return _Pressable(
      label: label,
      onPressed: onPressed,
      color: enabled ? color : context.colors.ink,
      child: SizedBox(
        width: double.infinity,
        height: height + inset,
        child: Padding(
          padding: EdgeInsets.fromLTRB(bandGutter, 0, bandGutter, inset),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(21, weight: 800, color: text),
                ),
              ),
              if (busy)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: text,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A player's band: their name justified edge to edge, with a small line
/// above it for whatever this screen has to say about them.
class PlayerBand extends StatelessWidget {
  final String name;
  final PlayerInk ink;
  final String? leading;
  final String? trailing;
  final VoidCallback? onTap;

  /// What a screen reader says for a band that does something when tapped.
  final String? actionLabel;

  /// Room to leave for the status bar or the home indicator, for a band that
  /// runs behind one.
  final double topInset;
  final double bottomInset;

  const PlayerBand({
    super.key,
    required this.name,
    required this.ink,
    this.leading,
    this.trailing,
    this.onTap,
    this.actionLabel,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final meta = uiText(14, weight: 700, color: ink.on);
    Widget line(String text, TextAlign align) => Flexible(
      child: Text(
        text,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: meta,
      ),
    );
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        bandGutter,
        10 + topInset,
        bandGutter,
        12 + bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (leading != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (leading != null) line(leading!, TextAlign.start),
                  const SizedBox(width: 12),
                  if (trailing != null) line(trailing!, TextAlign.end),
                ],
              ),
            ),
          Expanded(
            child: FitText(
              name.toUpperCase(),
              color: ink.on,
              semanticsLabel: name,
            ),
          ),
        ],
      ),
    );
    final action = actionLabel;
    if (action == null) return Material(color: ink.fill, child: content);
    return _Pressable(
      label: action,
      onPressed: onTap,
      color: ink.fill,
      child: content,
    );
  }
}

/// A block of colour that is one button to a screen reader.
///
/// The label, the button role and the tap live on the [Semantics] node, and
/// what's inside is excluded so a band is announced once rather than read out
/// in parts. The [InkWell] stays outside that exclusion, because excluding it
/// too would take away its focus action, and with it keyboard and Switch
/// Control access.
class _Pressable extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Widget child;

  const _Pressable({
    required this.label,
    required this.onPressed,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      child: Material(
        color: color,
        child: InkWell(
          onTap: onPressed,
          excludeFromSemantics: true,
          child: ExcludeSemantics(child: child),
        ),
      ),
    );
  }
}
