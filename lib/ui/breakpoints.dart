import 'package:flutter/widgets.dart';

/// The app's window-size thresholds, in one place.
///
/// Before this file the same numbers were written out in eight files:
/// 600 (mobile/desktop split), 720 (reading width), 1024 (extended
/// rail / detail split), 1440 (wide grid cap). The VALUES are
/// unchanged — this is a pure refactor, so every page must look
/// exactly as before. Two thresholds are new and not yet used by any
/// existing decision: 840 (expanded) and 1200 (large); they exist for
/// task 5's wide-layout work.
/// The new plan (2026-11-20) moved the detail/group splits from 1024
/// to 900 and capped the subject detail's left column at 880; those
/// live here as paneSplit and detailTextMaxWidth.
///
/// Note the two width bases in the app: the shell splits on the
/// WINDOW width, while inner pages (Browse, home, FacetedView) split
/// on their own CONTENT width, which is the window minus the 72/240
/// rail. Both bases use the same numbers; only the measured width
/// differs.
enum WindowSize { compact, medium, expanded, large }

class Breakpoints {
  /// Mobile/desktop split (shell bottom nav vs rail; Browse grid vs
  /// list; HScrollRow desktop affordances; FacetedView sheet).
  static const double medium = 600;

  /// First wide band; no existing decision keys off it yet.
  static const double expanded = 840;

  /// Second wide band; no existing decision keys off it yet.
  static const double large = 1200;

  /// Extended NavigationRail (1024). The detail splits used to share
  /// this number; they now use paneSplit (900) instead.
  static const double extendedRail = 1024;

  /// Detail/group panes switch to their two-pane layout at 900, not
  /// 1024: a pushed subject page has no rail so its width is the
  /// window width, and the group split measures the same pane width.
  static const double paneSplit = 900;

  /// Subject detail's left-column text cap (new plan, task 5).
  static const double detailTextMaxWidth = 880;

  /// Reading/text column cap (CenteredWidth default, topic split).
  static const double textMaxWidth = 720;

  /// Wide grid/row cap (Browse, user poster grids, topic split row).
  static const double gridMaxWidth = 1440;

  static WindowSize of(double width) {
    if (width < medium) return WindowSize.compact;
    if (width < expanded) return WindowSize.medium;
    if (width < large) return WindowSize.expanded;
    return WindowSize.large;
  }

  static WindowSize ofContext(BuildContext context) =>
      of(MediaQuery.sizeOf(context).width);

  /// Poster-grid column count from Browse's rule: a ~240 poster
  /// inside the 1440-capped row with 48 of horizontal padding,
  /// 2-5 columns. Kept exact — a plain (width / 240) would add a
  /// sixth column on very wide windows. The home feed masonry uses a
  /// different formula (card ~360) and is deliberately not this one.
  static int posterColumns(double width) =>
      ((width - 48) / 240).floor().clamp(2, 5);
}
