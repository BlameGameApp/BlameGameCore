import 'package:flutter/material.dart';

/// The game's palette.
///
/// A [ThemeExtension] rather than loose constants so screens read colours from
/// the theme instead of hardcoding them, and so the whole look can change in
/// one place. Player colours live in `ui/player_cosmetics.dart`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color ink;
  final Color paper;

  /// Secondary text on [paper] and [surface].
  final Color muted;

  /// Fields, list groups and buttons that aren't the screen's main action.
  final Color surface;

  /// The app's one brand colour: the main action on every screen, and the
  /// header that sits behind the title.
  final Color brand;

  /// Result feedback, and anything the player has to stop and read.
  final Color correct;
  final Color alert;

  const AppColors({
    required this.ink,
    required this.paper,
    required this.muted,
    required this.surface,
    required this.brand,
    required this.correct,
    required this.alert,
  });

  static const light = AppColors(
    ink: Color(0xFF000000),
    paper: Color(0xFFFFFFFF),
    muted: Color(0xFF666666),
    surface: Color(0xFFEBEBEB),
    brand: Color(0xFFFFC200),
    correct: Color(0xFF0B7A43),
    alert: Color(0xFFC82A0E),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => other ?? this;
}

/// Convenience: `context.colors.brand`.
extension AppColorsOf on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
}

ThemeData buildAppTheme() {
  const c = AppColors.light;
  final scheme = ColorScheme.fromSeed(seedColor: c.brand).copyWith(
    primary: c.ink,
    onPrimary: c.paper,
    surface: c.paper,
    onSurface: c.ink,
    error: c.alert,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    extensions: const [c],
    scaffoldBackgroundColor: c.paper,
    // This is a touch app: keep Material's 48x48 minimum tap target instead of
    // the host-adaptive density, which shrinks controls on desktop.
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.ink, width: 2),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    textTheme: base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall!.copyWith(
        fontWeight: FontWeight.w800,
      ),
      headlineSmall: base.textTheme.headlineSmall!.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium!.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: base.textTheme.bodyLarge!.copyWith(
        fontSize: 17,
        letterSpacing: 0,
      ),
      bodyMedium: base.textTheme.bodyMedium!.copyWith(
        fontSize: 15,
        letterSpacing: 0,
        color: c.muted,
      ),
    ),
  );
}
