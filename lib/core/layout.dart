import 'package:flutter/widgets.dart';

/// How much room the app has, decided in one place so every page agrees.
///
/// Follows Material 3 "window size classes":
///   compact  < 600   phones held upright
///   medium   600-839 small tablets, phones on their side
///   expanded 840-1199 tablets, small laptops (side menu appears here)
///   large    1200+   desktops (side menu shows labels)
///
/// One extra rule: a screen much taller than it is wide is a phone, even if it
/// reports a big width (a browser in "Desktop site" mode, or a very small
/// Display size setting). Phones are about 0.45-0.5 wide per 1 tall; upright
/// tablets are 0.62-0.75, so 0.6 separates them cleanly.
enum ScreenSize {
  compact,
  medium,
  expanded,
  large;

  static const double mediumFrom = 600;
  static const double expandedFrom = 840;
  static const double largeFrom = 1200;
  static const double phoneShape = 0.6;

  static ScreenSize forWidth(double width) => width >= largeFrom
      ? large
      : width >= expandedFrom
          ? expanded
          : width >= mediumFrom
              ? medium
              : compact;

  /// The size class of the whole window.
  static ScreenSize of(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    if (s.height > 0 && s.width / s.height < phoneShape) return compact;
    return forWidth(s.width);
  }

  /// The size class of one part of a page (from a LayoutBuilder): its own
  /// width, but never bigger than the window's class.
  static ScreenSize within(BuildContext context, double width) {
    final window = of(context);
    final area = forWidth(width);
    return area.index < window.index ? area : window;
  }

  bool operator >=(ScreenSize other) => index >= other.index;

  /// How many columns a grid of cards should use.
  int columns({int compact = 1, int medium = 2, int expanded = 3, int large = 3}) => switch (this) {
        ScreenSize.compact => compact,
        ScreenSize.medium => medium,
        ScreenSize.expanded => expanded,
        ScreenSize.large => large,
      };
}
