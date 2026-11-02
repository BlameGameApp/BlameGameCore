import 'package:flutter/material.dart';

/// The game's palette.
///
/// A [ThemeExtension] rather than loose constants so screens read colours from
/// the theme instead of hardcoding them, and so the whole look can change in
/// one place. Everything is a flat ink: there are no tints, and text sits on a
/// solid colour rather than a translucent one. Player colours live in
/// `ui/player_cosmetics.dart`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Pure black and white, not a tinted near-black: the photos are the only
  /// thing on the round screen that should carry a colour cast.
  final Color ink;
  final Color paper;

  /// The two title bands, and the first two players in every room.
  final Color marigold;
  final Color vermilion;

  /// Actions that aren't the screen's main one.
  final Color cobalt;

  /// Secondary text on [paper] and on [ink].
  final Color inkMuted;
  final Color paperMuted;

  const AppColors({
    required this.ink,
    required this.paper,
    required this.marigold,
    required this.vermilion,
    required this.cobalt,
    required this.inkMuted,
    required this.paperMuted,
  });

  static const flat = AppColors(
    ink: Color(0xFF000000),
    paper: Color(0xFFFFFFFF),
    marigold: Color(0xFFFFC200),
    vermilion: Color(0xFFEE3A1C),
    cobalt: Color(0xFF1B3BD4),
    inkMuted: Color(0xFF666666),
    paperMuted: Color(0xFFA6A6A6),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => other ?? this;
}

/// Convenience: `context.colors.vermilion`.
extension AppColorsOf on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.flat;
}

const appFontFamily = 'Anybody';

/// Sentence-case interface text.
///
/// Always goes through here because Anybody's default instance is wght 100:
/// a style that names the family but no weight renders as a hairline. Setting
/// `fontWeight` doesn't move a variable font's axis, it only asks the engine
/// to fake a bold on top of the thin master.
TextStyle uiText(double size, {double weight = 500, Color? color}) {
  return TextStyle(
    fontFamily: appFontFamily,
    fontSize: size,
    letterSpacing: 0,
    height: 1.25,
    color: color,
    fontVariations: [FontVariation.weight(weight)],
  );
}

ThemeData buildAppTheme() {
  const c = AppColors.flat;
  final scheme = ColorScheme.light(
    primary: c.ink,
    onPrimary: c.paper,
    secondary: c.cobalt,
    onSecondary: c.paper,
    surface: c.paper,
    onSurface: c.ink,
    error: c.vermilion,
    onError: c.ink,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  // Every slot, not just the ones the screens name: dialogs, tooltips and text
  // fields read their own slots, and any one left out falls back to wght 100.
  TextStyle body(TextStyle? style, {double weight = 500}) => style!.copyWith(
    fontFamily: appFontFamily,
    letterSpacing: 0,
    fontVariations: [FontVariation.weight(weight)],
  );
  final t = base.textTheme;

  return base.copyWith(
    extensions: [c],
    scaffoldBackgroundColor: c.ink,
    // This is a touch app: keep Material's 48x48 minimum tap target instead of
    // the host-adaptive density, which shrinks controls on desktop.
    visualDensity: VisualDensity.standard,
    // A pressed band darkens at once. A ripple spreading across a full-width
    // block of flat colour is the one thing here that would read as Material.
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x29000000),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.ink),
    textTheme: TextTheme(
      displayLarge: body(t.displayLarge, weight: 900),
      displayMedium: body(t.displayMedium, weight: 900),
      displaySmall: body(t.displaySmall, weight: 900),
      headlineLarge: body(t.headlineLarge, weight: 800),
      headlineMedium: body(t.headlineMedium, weight: 800),
      headlineSmall: body(t.headlineSmall, weight: 800),
      titleLarge: body(t.titleLarge, weight: 800),
      titleMedium: body(t.titleMedium, weight: 700),
      titleSmall: body(t.titleSmall, weight: 700),
      bodyLarge: body(t.bodyLarge),
      bodyMedium: body(t.bodyMedium),
      bodySmall: body(t.bodySmall),
      labelLarge: body(t.labelLarge, weight: 700),
      labelMedium: body(t.labelMedium, weight: 700),
      labelSmall: body(t.labelSmall, weight: 700),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      behavior: SnackBarBehavior.fixed,
      elevation: 0,
      contentTextStyle: uiText(15, weight: 600, color: c.paper),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.ink),
      textStyle: uiText(13, weight: 600, color: c.paper),
    ),
  );
}
