import 'package:flutter/widgets.dart';

/// Nocturne design tokens — the single source of colour, spacing, radius and
/// elevation for the app UI.
///
/// Ported verbatim from the handoff package's `nocturne-design-system/
/// styles.css` `:root` block. Nocturne is a **dark-only** system: a quiet
/// near-neutral blue-grey ground with one blurple accent used as a line and a
/// glow rather than a flood. There is deliberately no light palette — the
/// design package does not define one.
///
/// Rules of use (from the system's own guidance):
/// * never hard-code a colour, radius or spacing a token already carries;
/// * keep chroma low outside the accent — surfaces, borders and muted text
///   come from the neutral ramp;
/// * do not flood large areas with the accent; primary actions are **outlined**
///   (1px accent border on transparent), not filled;
/// * do not use pure black or pure white;
/// * hierarchy is size and space — headings never go past weight 500.
abstract final class NocturneColors {
  /// The page ground.
  static const Color bg = Color(0xFF161826);

  /// Filled content surfaces (cards, sheets, inputs).
  static const Color surface = Color(0xFF232532);

  /// Primary body/heading text.
  static const Color text = Color(0xFFE9E9ED);

  /// The single accent — a blurple in the product's own Pro-accent hue.
  static const Color accent = Color(0xFF9184D9);

  /// The system's mono-scheme stand-in; reads as the same role as [accent].
  static const Color accent2 = Color(0xFFA7A1DB);

  /// `color-mix(in srgb, #e9e9ed 16%, transparent)`.
  static const Color divider = Color(0x29E9E9ED);

  // --- Tonal ramps -------------------------------------------------------
  // Generated in OKLCH on one shared lightness scale, so the same step of any
  // role carries the same visual weight. On this dark ground: 700–900 for
  // tinted fills, hovers and subtle borders; 500 as the role's base; 100–300
  // for text on those tints and for pressed states.

  static const Color neutral100 = Color(0xFFF3F5FE);
  static const Color neutral200 = Color(0xFFE4E7F5);
  static const Color neutral300 = Color(0xFFCFD3E5);
  static const Color neutral400 = Color(0xFFB2B6CA);
  static const Color neutral500 = Color(0xFF9397AB);
  static const Color neutral600 = Color(0xFF75798C);
  static const Color neutral700 = Color(0xFF595D6C);
  static const Color neutral800 = Color(0xFF3F424D);
  static const Color neutral900 = Color(0xFF292B31);

  static const Color accent100 = Color(0xFFF5F4FF);
  static const Color accent200 = Color(0xFFE7E5FE);
  static const Color accent300 = Color(0xFFD2CEFD);
  static const Color accent400 = Color(0xFFB5ABFC);
  static const Color accent500 = Color(0xFF968AE0);
  static const Color accent600 = Color(0xFF796CBF);
  static const Color accent700 = Color(0xFF5D5294);
  static const Color accent800 = Color(0xFF423A6A);
  static const Color accent900 = Color(0xFF2B2741);

  // --- Text tints --------------------------------------------------------
  // The artboards express secondary text as alpha over [text] rather than as
  // ramp steps; these are those exact values.

  /// Secondary body copy — `rgba(233,233,237,0.62)`.
  static const Color textMuted = Color(0x9EE9E9ED);

  /// Tertiary/caption text — `rgba(233,233,237,0.55)`.
  static const Color textSubtle = Color(0x8CE9E9ED);

  /// Faint metadata — `rgba(233,233,237,0.45)`.
  static const Color textFaint = Color(0x73E9E9ED);

  /// Inactive outlines — `rgba(233,233,237,0.3)`.
  static const Color outlineFaint = Color(0x4DE9E9ED);

  /// Very low tint fill, e.g. the iOS keypad key — `rgba(233,233,237,0.09)`.
  static const Color fillFaint = Color(0x17E9E9ED);

  // --- Semantic ----------------------------------------------------------
  // The system is mono by design; success/warning/danger borrow the ramps so
  // they stay in the same desaturated family instead of introducing new hues.

  /// Confirmed / success.
  static const Color success = Color(0xFF7FB894);

  /// Pending / attention.
  static const Color warning = Color(0xFFD9C184);

  /// Failure / destructive.
  static const Color danger = Color(0xFFD98A8A);
}

/// The compact spacing scale — density 0.7×, on purpose.
abstract final class NocturneSpacing {
  static const double x1 = 2.8;
  static const double x2 = 5.6;
  static const double x3 = 8.4;
  static const double x4 = 11.2;
  static const double x6 = 16.8;
  static const double x8 = 22.4;

  /// Standard screen gutter used throughout the artboards.
  static const double gutter = 20;
}

/// Corner radii. 8px is the system default.
abstract final class NocturneRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 14;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}

/// Elevation. On a dark ground elevation is a hairline edge plus ambient
/// darkness — never a stack of heavy shadows.
abstract final class NocturneShadows {
  /// `0 0 0 1px #3f424d` — a hairline edge only. Drawn as a border, not a
  /// shadow, because Flutter has no spread-only inset equivalent.
  static const Color edgeSm = NocturneColors.neutral800;
  static const Color edgeMd = NocturneColors.neutral700;
  static const Color edgeLg = NocturneColors.neutral500;

  static const List<BoxShadow> md = <BoxShadow>[
    BoxShadow(color: Color(0x8C000000), blurRadius: 18, offset: Offset(0, 6)),
  ];

  static const List<BoxShadow> lg = <BoxShadow>[
    BoxShadow(color: Color(0xA6000000), blurRadius: 40, offset: Offset(0, 16)),
  ];
}

/// Type. Inter at medium weight for headings over Inter for body; hierarchy
/// comes from size and space, so headings stay at weight 500.
abstract final class NocturneType {
  /// Bundled as an asset so the UI renders identically offline and on every
  /// platform. Falls back to the platform UI font if the asset is missing.
  static const String family = 'Inter';

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
}
