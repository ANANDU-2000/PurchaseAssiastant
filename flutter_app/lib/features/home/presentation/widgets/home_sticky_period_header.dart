import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/theme/hexa_colors.dart';
import 'home_period_filter_row.dart';

/// Sticky period chips for owner dashboard scroll.
class HomeStickyPeriodHeader extends SliverPersistentHeaderDelegate {
  HomeStickyPeriodHeader();

  /// Phone: single scroll row + one subtitle line.
  static const double _phoneExtent = 58;

  /// Tablet+: wrapping chips may need a second row.
  static const double _wideExtent = 88;

  @override
  double get minExtent => _phoneExtent;

  @override
  double get maxExtent => _wideExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final wide = MediaQuery.sizeOf(context).width >= HexaBreakpoints.tablet;
    return SizedBox.expand(
      child: Material(
        color: HexaColors.brandBackground,
        elevation: overlapsContent ? 1 : 0,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const HomePeriodFilterRow(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  child: Text(
                    wide
                        ? 'Applies to purchase center and warehouse activity'
                        : 'Applies to purchase & warehouse',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant HomeStickyPeriodHeader oldDelegate) => true;
}
