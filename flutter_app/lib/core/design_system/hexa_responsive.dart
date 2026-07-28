import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hexa_ds_tokens.dart';
import 'hexa_operational_tokens.dart';

/// Spec-aligned breakpoints (single source of truth).
///
/// | Token | Width | Use |
/// |---|---|---|
/// | Phone | &lt;600 | Bottom nav, single column |
/// | Tablet | 600–1023 | 72px icon rail |
/// | Desktop | ≥1024 | Master-detail, dense KPI grids |
/// | Ultra | ≥1600 | Same density, more side padding |
const double kMobileMax = 599;
const double kTabletMin = 600;
const double kDesktopMin = 1024;
const double kUltraWideMin = 1600;

/// Navigation rail / barcode split threshold (legacy alias).
const double kNavigationRailMin = 900;

/// Shell: bottom navigation only below this width.
const double kShellBottomNavMax = 600;

/// Shell: left compact rail from tablet up.
const double kShellRailMin = 600;

/// Shell: extended rail with labels (unused — compact rail only on web).
const double kShellRailExtendedMin = 900;

/// Compact side-nav width (icons only). Keep ≥72 — Material [NavigationRail]
/// defaults to minWidth 72; narrower caps caused Flutter web shell blanks.
const double kShellCompactRailWidth = 72;

/// Extended rail / branded sidebar width target on desktop.
const double kDesktopSidebarWidth = 240;

enum HexaViewportClass {
  compactPhone,
  phone,
  tablet,
  desktop,
  ultraWide,
}

/// Flutter-native responsive primitives for Harisree app surfaces.
///
/// Keep page-specific layout choices local, but route all breakpoints, gutters,
/// sheet constraints, and touch-target minimums through this file.
abstract final class HexaBreakpoints {
  const HexaBreakpoints._();

  static const double compactPhone = 360;
  static const double phone = 600;
  static const double tablet = 900;
  /// Aligned with [kDesktopMin] — master-detail and dense dashboards.
  static const double desktop = kDesktopMin;
  static const double ultraWide = kUltraWideMin;

  /// Layout width; 0 when MediaQuery is not ready (web first frame).
  static double _layoutWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (!w.isFinite || w <= 0) return 0;
    return w;
  }

  static HexaViewportClass classify(double width) {
    if (!width.isFinite || width <= 0) return HexaViewportClass.phone;
    if (width < compactPhone) return HexaViewportClass.compactPhone;
    if (width < phone) return HexaViewportClass.phone;
    if (width < tablet) return HexaViewportClass.tablet;
    if (width < ultraWide) return HexaViewportClass.desktop;
    return HexaViewportClass.ultraWide;
  }

  static bool isCompact(BuildContext context) {
    final w = _layoutWidth(context);
    return w > 0 && w < compactPhone;
  }

  static bool isPhone(BuildContext context) {
    final w = _layoutWidth(context);
    return w == 0 || w < phone;
  }

  static bool isTabletOrLarger(BuildContext context) {
    final w = _layoutWidth(context);
    return w > 0 && w >= tablet;
  }

  static bool isDesktop(BuildContext context) {
    final w = _layoutWidth(context);
    return w > 0 && w >= desktop;
  }

  /// Master-detail and desktop dashboard grids (spec: ≥1024).
  static bool isDesktopLayout(BuildContext context) {
    final w = _layoutWidth(context);
    return w > 0 && w >= kDesktopMin;
  }

  static bool isNavigationRail(BuildContext context) {
    final w = _layoutWidth(context);
    return w > 0 && w >= kNavigationRailMin;
  }
}

double _hexaLayoutWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (!w.isFinite || w <= 0) return 0;
  return w;
}

/// Layout helpers aligned to DESKTOP_DESIGN_SPEC breakpoints.
extension HexaLayoutContext on BuildContext {
  bool get isMobileLayout {
    final w = _hexaLayoutWidth(this);
    return w == 0 || w <= kMobileMax;
  }

  bool get isTabletLayout {
    final w = _hexaLayoutWidth(this);
    return w > 0 && w >= kTabletMin && w < kDesktopMin;
  }

  bool get isDesktopLayout {
    final w = _hexaLayoutWidth(this);
    return w > 0 && w >= kDesktopMin;
  }

  bool get showsNavigationRail {
    final w = _hexaLayoutWidth(this);
    return w > 0 && w >= kNavigationRailMin;
  }
}

abstract final class HexaResponsive {
  const HexaResponsive._();

  static const double minTouchTarget = 48;
  static const double minReadableFont = 11;
  static const double maxContentWidth = 1180;
  /// Owner home operational body — wider than generic content to cut side gutters.
  static const double maxHomeContentWidth = 1440;
  static const double maxFormWidth = 720;
  static const double maxSheetWidth = 640;

  /// Reports desktop chrome (period nav + filter drawer).
  static const double reportsPeriodNavWidth = 200;
  static const double reportsPeriodNavCompact = 160;
  static const double reportsFilterDrawerWidth = 280;
  static const double reportsFilterDrawerCompact = 220;

  /// Desktop content max for standard pages (window width bands).
  /// Body is already window − rail; do not subtract [kShellCompactRailWidth] again.
  static double desktopContentMax(double windowW) {
    if (windowW < 1280) return 1100;
    if (windowW < 1366) return 1120; // 1280
    if (windowW < 1440) return 1200; // 1366
    if (windowW < 1600) return 1280; // 1440
    if (windowW < 1920) return 1400; // 1600
    return 1520; // ≥1920
  }

  /// Owner home — fills more of the body so 1600/1920 are not empty gutters.
  static double desktopHomeContentMax(double windowW) {
    if (windowW < 1280) return 1180;
    if (windowW < 1366) return 1160;
    if (windowW < 1440) return 1240;
    if (windowW < 1600) return 1320;
    if (windowW < 1920) return 1480;
    return 1680;
  }

  /// Settings / edit forms.
  static double desktopFormMax(double windowW) {
    if (windowW < 1600) return 720;
    if (windowW < 1920) return 760;
    return 800;
  }

  /// Master-detail preview/detail column width (fixed pane, not flex-stretch).
  static double desktopDetailPaneMax(double windowW) {
    if (windowW < 1440) return 420;
    if (windowW < 1600) return 480;
    if (windowW < 1920) return 520;
    return 560;
  }

  /// Detail *card* inside a flex pane (stock/purchase) — grows with screen.
  static double desktopDetailContentMax(double windowW) {
    if (windowW < 1440) return 720;
    if (windowW < 1600) return 760;
    if (windowW < 1920) return 820;
    return 880;
  }

  /// Resolve a requested max against desktop bands when callers pass the
  /// standard constants (mobile callers keep the literal width).
  static double resolveDesktopMax(double windowW, double requested) {
    if (windowW < kDesktopMin) return requested;
    if ((requested - maxHomeContentWidth).abs() < 0.5) {
      return desktopHomeContentMax(windowW);
    }
    if ((requested - maxContentWidth).abs() < 0.5) {
      return desktopContentMax(windowW);
    }
    if ((requested - maxFormWidth).abs() < 0.5 ||
        (requested - 720).abs() < 0.5) {
      return desktopFormMax(windowW);
    }
    if ((requested - 900).abs() < 0.5) {
      return desktopContentMax(windowW);
    }
    return requested;
  }

  static double desktopPageGutter(
    double windowW, {
    bool operational = false,
  }) {
    if (windowW < 1280) return operational ? 20 : 24;
    if (windowW < 1440) return operational ? 20 : 24; // 1280–1439
    if (windowW < 1600) return operational ? 24 : 28; // 1440
    if (windowW < 1920) return operational ? 28 : 32; // 1600
    return operational ? 32 : 40; // ≥1920
  }

  /// Vertical gap between home/report sections (tighter on phones).
  static double sectionGap(BuildContext context) {
    final width = _hexaLayoutWidth(context);
    if (width == 0 || width <= kMobileMax) return HexaOp.mobileSectionGap;
    if (width < kDesktopMin) return HexaOp.sectionGap;
    return HexaOp.desktopSectionGap;
  }

  static double pageGutter(
    BuildContext context, {
    bool operational = false,
  }) {
    final width = _hexaLayoutWidth(context);
    if (width == 0 || width < HexaBreakpoints.compactPhone) return 12;
    if (width >= HexaBreakpoints.desktop) {
      return desktopPageGutter(width, operational: operational);
    }
    if (operational) return HexaOp.pageGutter;
    if (width >= HexaBreakpoints.tablet) return 24;
    return 16;
  }

  static EdgeInsets pagePadding(
    BuildContext context, {
    bool operational = false,
    double top = 8,
    double bottom = 24,
  }) {
    final gutter = pageGutter(context, operational: operational);
    return EdgeInsets.fromLTRB(gutter, top, gutter, bottom);
  }

  static double clampedFont(double value) => math.max(minReadableFont, value);

  static double adaptiveSheetMaxHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final ratio = landscape ? 0.92 : 0.86;
    return math.max(280, size.height * ratio);
  }
}

class HexaResponsiveCenter extends StatelessWidget {
  const HexaResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = HexaResponsive.maxContentWidth,
    this.padding,
    this.alignTop = true,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    // Never use Align/Center around scroll sliver children on Flutter web —
    // unbounded height + expand-to-fit blanks the page. Pad horizontally when
    // the parent is wider than [maxWidth] instead.
    // Desktop: pad only the *right* so content stays flush with the sidebar.
    // Phone/tablet: keep symmetric padding (unchanged).
    final pad = padding ?? HexaResponsive.pagePadding(context);
    final windowW = _hexaLayoutWidth(context);
    final desktop = windowW >= kDesktopMin;
    final effectiveMax =
        HexaResponsive.resolveDesktopMax(windowW, maxWidth);
    return Padding(
      padding: pad,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          Widget content = child;
          if (w.isFinite && w > effectiveMax) {
            final extra = w - effectiveMax;
            content = Padding(
              padding: desktop
                  ? EdgeInsets.only(right: extra)
                  : EdgeInsets.symmetric(horizontal: extra / 2),
              child: child,
            );
          }
          return content;
        },
      ),
    );
  }
}

class HexaResponsiveSheetViewport extends StatelessWidget {
  const HexaResponsiveSheetViewport({
    super.key,
    required this.child,
    this.maxWidth = HexaResponsive.maxSheetWidth,
    this.padding,
    this.bottomExtra = 16,
    this.scrollController,
    this.compact = false,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final double bottomExtra;
  final ScrollController? scrollController;
  /// When true, sheet height hugs content (action menus). Avoids full-screen white gap.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final effectivePadding = padding ??
        EdgeInsets.fromLTRB(
          HexaResponsive.pageGutter(context, operational: true),
          compact ? 8 : 4,
          HexaResponsive.pageGutter(context, operational: true),
          bottomExtra + bottomSafe,
        );

    final padded = Padding(padding: effectivePadding, child: child);

    if (compact) {
      return AnimatedPadding(
        duration: HexaDsMotion.fast,
        curve: HexaDsMotion.enter,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: padded,
            ),
          ),
        ),
      );
    }

    return AnimatedPadding(
      duration: HexaDsMotion.fast,
      curve: HexaDsMotion.enter,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: HexaResponsive.adaptiveSheetMaxHeight(context),
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: effectivePadding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard bottom sheet host — compact sheets hug content (no top blank gap).
Future<T?> showHexaBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool compact = true,
  EdgeInsetsGeometry? padding,
  double maxWidth = HexaResponsive.maxSheetWidth,
  ShapeBorder? shape,
}) {
  if (HexaBreakpoints.isDesktop(context)) {
    // Desktop uses a dialog (not a bottom sheet).
    // - compact: shrink-wrap scroll so field sheets size to content (Stock Update).
    // - !compact: fixed height so Column + Expanded list sheets do not collapse.
    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final mq = MediaQuery.sizeOf(ctx);
        final windowW = mq.width;
        final formCap = HexaResponsive.desktopFormMax(windowW);
        // Allow up to form band on large desktops; keep phone-dialog feel on smaller.
        final upper = math.min(formCap, mq.width * 0.48);
        final sheetW = maxWidth.clamp(320.0, upper).toDouble();
        final inset = EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        );
        final contentPadding =
            padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 16);

        final Widget body;
        if (compact) {
          body = ListView(
            shrinkWrap: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: contentPadding,
            children: [child],
          );
        } else {
          final padded = padding == null
              ? Padding(padding: contentPadding, child: child)
              : (padding == EdgeInsets.zero
                  ? child
                  : Padding(padding: padding, child: child));
          body = padded;
        }

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          shape: shape ??
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
          child: SizedBox(
            width: sheetW,
            height: compact ? null : mq.height * 0.88,
            child: compact
                ? ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: mq.height * 0.88),
                    child: Material(
                      color: Theme.of(ctx).dialogTheme.backgroundColor ??
                          Theme.of(ctx).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: AnimatedPadding(
                        duration: HexaDsMotion.fast,
                        curve: HexaDsMotion.enter,
                        padding: inset,
                        child: body,
                      ),
                    ),
                  )
                : Material(
                    color: Theme.of(ctx).dialogTheme.backgroundColor ??
                        Theme.of(ctx).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedPadding(
                      duration: HexaDsMotion.fast,
                      curve: HexaDsMotion.enter,
                      padding: inset,
                      child: body,
                    ),
                  ),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: shape ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
    builder: (ctx) => HexaResponsiveSheetViewport(
      compact: compact,
      padding: padding,
      maxWidth: maxWidth,
      child: child,
    ),
  );
}

class HexaAccessibleFilterChip extends StatelessWidget {
  const HexaAccessibleFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          const BoxConstraints(minHeight: HexaResponsive.minTouchTarget),
      child: FilterChip(
        label: Text(
          label,
          style: HexaDsType.label(compact ? 11 : 12).copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        selected: selected,
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        onSelected: onSelected,
      ),
    );
  }
}
