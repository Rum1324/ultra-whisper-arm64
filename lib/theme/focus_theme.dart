import 'package:flutter/material.dart';

/// The Focus design system, as Flutter values.
///
/// Source of truth: the "Focus" design system artifact
/// (https://claude.ai/artifact/7HdngMCcJbaFSKVwZBQphA), `project/tokens.json`.
/// Names follow the tokens (`ink-2` → [FocusColors.ink2]) so a value here can
/// be checked against the artifact by eye. Copy new values from there rather
/// than tuning them here.
///
/// Two palettes:
/// - [FocusColors] follows the system light/dark mode. The settings window
///   uses it.
/// - [FocusIsland] is always black, in both modes. Focus designed it for
///   floating Mac UI over other apps, which is what the dictation overlay and
///   the meeting panel are.
@immutable
class FocusColors extends ThemeExtension<FocusColors> {
  const FocusColors({
    required this.bg,
    required this.surface,
    required this.sheet,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.fill,
    required this.accent,
    required this.accentTint,
    required this.onAccent,
    required this.ok,
    required this.okTint,
    required this.warn,
    required this.warnTint,
    required this.bad,
    required this.inverse,
    required this.onInverse,
  });

  /// The page ground.
  final Color bg;

  /// Objects on the ground: cards, rows, chips.
  final Color surface;

  /// The fill of text inputs.
  final Color sheet;

  /// Primary text.
  final Color ink;

  /// Secondary text: explanations, details, metadata.
  final Color ink2;

  /// Tertiary text. Fails contrast on purpose: never for anything actionable.
  final Color ink3;

  /// Hairlines: dividers, input and outline-button borders.
  final Color line;

  /// Quiet fills: tracks, hovers, neutral pills.
  final Color fill;

  /// Live and now only, plus the focus ring.
  final Color accent;
  final Color accentTint;
  final Color onAccent;

  /// Done and progress; also a switch that is on.
  final Color ok;
  final Color okTint;

  /// Needs attention but not broken.
  final Color warn;
  final Color warnTint;

  /// Late and destructive.
  final Color bad;

  /// The one inverted object: the primary (ink) button.
  final Color inverse;
  final Color onInverse;

  static const light = FocusColors(
    bg: Color(0xFFE8E9ED),
    surface: Color(0xFFFFFFFF),
    sheet: Color(0xFFF6F7F9),
    ink: Color(0xFF15171C),
    ink2: Color(0xFF697080),
    ink3: Color(0xFF9AA0AB),
    line: Color.fromRGBO(21, 23, 28, .08),
    fill: Color.fromRGBO(21, 23, 28, .06),
    accent: Color(0xFF3B5BDB),
    accentTint: Color.fromRGBO(59, 91, 219, .08),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF2F9E44),
    okTint: Color.fromRGBO(47, 158, 68, .12),
    warn: Color(0xFFB8640B),
    warnTint: Color(0xFFFFF1DB),
    bad: Color(0xFFC92A5A),
    inverse: Color(0xFF15171C),
    onInverse: Color(0xFFFFFFFF),
  );

  static const dark = FocusColors(
    bg: Color(0xFF0F1115),
    surface: Color(0xFF25262A),
    sheet: Color(0xFF1C1E22),
    ink: Color(0xFFFFFFFF),
    ink2: Color(0xFFA4A5A6),
    ink3: Color(0xFF6F7073),
    line: Color.fromRGBO(255, 255, 255, .08),
    fill: Color.fromRGBO(255, 255, 255, .09),
    accent: Color(0xFF7CC4FF),
    accentTint: Color.fromRGBO(124, 196, 255, .14),
    onAccent: Color(0xFF0F1115),
    ok: Color(0xFF33D67A),
    okTint: Color.fromRGBO(51, 214, 122, .14),
    warn: Color(0xFFFFBF2E),
    warnTint: Color(0xFF312919),
    bad: Color(0xFFFF544A),
    inverse: Color(0xFFFFFFFF),
    onInverse: Color(0xFF000000),
  );

  /// The theme's palette, or [light] under a theme that does not carry one
  /// (widget tests pump a bare MaterialApp).
  static FocusColors of(BuildContext context) =>
      Theme.of(context).extension<FocusColors>() ?? light;

  @override
  FocusColors copyWith() => this;

  @override
  FocusColors lerp(FocusColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return FocusColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      sheet: l(sheet, other.sheet),
      ink: l(ink, other.ink),
      ink2: l(ink2, other.ink2),
      ink3: l(ink3, other.ink3),
      line: l(line, other.line),
      fill: l(fill, other.fill),
      accent: l(accent, other.accent),
      accentTint: l(accentTint, other.accentTint),
      onAccent: l(onAccent, other.onAccent),
      ok: l(ok, other.ok),
      okTint: l(okTint, other.okTint),
      warn: l(warn, other.warn),
      warnTint: l(warnTint, other.warnTint),
      bad: l(bad, other.bad),
      inverse: l(inverse, other.inverse),
      onInverse: l(onInverse, other.onInverse),
    );
  }
}

/// The black island palette: identical in light and dark.
abstract final class FocusIsland {
  static const ground = Color(0xFF000000);
  static const ink = Color(0xFFFFFFFF);
  static const ink2 = Color.fromRGBO(255, 255, 255, .62);
  static const ink3 = Color.fromRGBO(255, 255, 255, .40);
  static const fill = Color.fromRGBO(255, 255, 255, .09);
  static const hover = Color.fromRGBO(255, 255, 255, .14);

  /// Level dots. Glowing marks on the island, never text on a light ground.
  static const levelCalm = Color(0xFF33D67A);
  static const levelWatch = Color(0xFFFFBF2E);
  static const levelRisk = Color(0xFFFF544A);
  static const levelOffline = Color(0xFF8C8C8C);

  /// `shadow-island`: only while the island is open.
  static const shadow = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, .5),
      offset: Offset(0, 10),
      blurRadius: 44,
    ),
  ];
}

/// Radii. Controls are pills; containers round more as they grow.
abstract final class FocusRadius {
  static const r6 = Radius.circular(6);
  static const r10 = Radius.circular(10);
  static const r12 = Radius.circular(12);
  static const r14 = Radius.circular(14);
  static const r16 = Radius.circular(16);
  static const r26 = Radius.circular(26);
  static const pill = Radius.circular(999);
}

/// Text styles from the Focus type scale, at a 16px root.
///
/// The Mac face is the system one (SF Pro), which is Flutter's default on
/// macOS, so no family is set. Weights stay between 400 and 600; Focus's 560
/// is drawn through the variable axis where the face has one.
abstract final class FocusText {
  static const _w560 = [FontVariation('wght', 560)];
  static const _tabular = [FontFeature.tabularFigures()];

  /// Card and group titles.
  static const title = TextStyle(
    fontSize: 16.8,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontVariations: _w560,
  );

  /// A window or sheet header.
  static const sheetTitle = TextStyle(
    fontSize: 16.8,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  static const body = TextStyle(fontSize: 16, height: 1.45);

  /// Tabs, chips, buttons.
  static const control = TextStyle(
    fontSize: 14.72,
    height: 1.45,
    fontWeight: FontWeight.w500,
  );

  /// The line under a title. Tabular figures; use in ink-2.
  static const detail = TextStyle(
    fontSize: 14.4,
    height: 1.45,
    fontFeatures: _tabular,
  );

  /// Small outline buttons.
  static const buttonSm = TextStyle(
    fontSize: 13.6,
    height: 1.45,
    fontWeight: FontWeight.w500,
  );

  /// Small print and source lines.
  static const caption = TextStyle(fontSize: 13.12, height: 1.45);

  /// Group headers. Pass the text UPPERCASE; use in ink-2.
  static const label = TextStyle(
    fontSize: 12.8,
    height: 1.45,
    fontWeight: FontWeight.w600,
    letterSpacing: 12.8 * .04,
  );

  /// Tags and pills.
  static const tag = TextStyle(
    fontSize: 11.52,
    height: 1.45,
    fontWeight: FontWeight.w600,
  );

  /// Diagnostics only.
  static const mono = TextStyle(
    fontFamily: 'Menlo',
    fontSize: 12.48,
    height: 1.45,
  );

  // The island's Mac scale (`mac-*` styles): smaller, set in the system face.

  /// An island section label. Pass the text UPPERCASE.
  static const islandLabel = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w600,
    letterSpacing: .7,
    color: FocusIsland.ink3,
  );

  /// The one thing the island is about.
  static const islandNow = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: FocusIsland.ink,
  );

  /// Facts under it. Tabular figures.
  static const islandMeta = TextStyle(
    fontSize: 11.5,
    color: FocusIsland.ink2,
    fontFeatures: _tabular,
  );

  /// Pill button text.
  static const islandPill = TextStyle(
    fontSize: 11.5,
    height: 1,
    fontWeight: FontWeight.w500,
  );
}

/// The Material theme for a window that follows the system appearance.
ThemeData focusTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? FocusColors.dark : FocusColors.light;
  const pill = StadiumBorder();
  final focusRing = BorderSide(color: c.accent, width: 2);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.bad,
    onError: c.onInverse,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.ink2,
    outline: c.line,
    outlineVariant: c.line,
    surfaceContainerHighest: c.fill,
    inverseSurface: c.inverse,
    onInverseSurface: c.onInverse,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.surface,
    dividerColor: c.line,
    extensions: [c],
    textTheme: TextTheme(
      titleMedium: FocusText.title.copyWith(color: c.ink),
      bodyLarge: FocusText.body.copyWith(color: c.ink),
      bodyMedium: FocusText.body.copyWith(fontSize: 14.4, color: c.ink),
      bodySmall: FocusText.caption.copyWith(color: c.ink2),
      labelLarge: FocusText.control,
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    // Primary action: the ink button.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.inverse,
        foregroundColor: c.onInverse,
        shape: pill,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        textStyle: FocusText.control,
      ),
    ),
    // Everything else: the outline button.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        side: BorderSide(color: c.line),
        shape: pill,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        textStyle: FocusText.control,
      ),
    ),
    // Minor actions: the ghost button.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.ink2,
        shape: pill,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        textStyle: FocusText.control,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.ink2,
        minimumSize: const Size(40, 40),
        hoverColor: c.fill,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.ok : c.ink3,
      ),
      thumbColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
      trackOutlineColor: const WidgetStatePropertyAll(Color(0x00000000)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.ok : null,
      ),
      checkColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
      side: BorderSide(color: c.ink3, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.ink : c.ink3,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accent,
      inactiveTrackColor: c.fill,
      thumbColor: c.surface,
      overlayColor: c.accentTint,
      trackHeight: 4,
      valueIndicatorColor: c.inverse,
      valueIndicatorTextStyle: FocusText.control.copyWith(color: c.onInverse),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.ok,
      linearTrackColor: c.fill,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.sheet,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      hintStyle: TextStyle(color: c.ink3),
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(FocusRadius.r10),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(FocusRadius.r10),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(FocusRadius.r10),
        borderSide: focusRing,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      side: BorderSide(color: c.line),
      shape: pill,
      labelStyle: FocusText.buttonSm.copyWith(color: c.ink),
      deleteIconColor: c.ink2,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(FocusRadius.r14),
        side: BorderSide(color: c.line),
      ),
      textStyle: FocusText.control.copyWith(color: c.ink),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.inverse,
        borderRadius: const BorderRadius.all(FocusRadius.pill),
      ),
      textStyle: FocusText.caption.copyWith(color: c.onInverse),
    ),
  );
}
