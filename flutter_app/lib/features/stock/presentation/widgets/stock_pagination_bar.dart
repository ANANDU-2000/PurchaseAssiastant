import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';

/// Prev / next controls for merged stock list (48dp targets).
class StockPaginationBar extends StatelessWidget {
  const StockPaginationBar({
    super.key,
    required this.showingCount,
    required this.totalCount,
    required this.currentPage,
    required this.maxPage,
    required this.onPrev,
    required this.onNext,
    this.loading = false,
    this.scrollOnly = false,
  });

  final int showingCount;
  final int totalCount;
  final int currentPage;
  final int maxPage;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool loading;

  /// Infinite scroll: show counts only (no prev/next page buttons).
  final bool scrollOnly;

  @override
  Widget build(BuildContext context) {
    final canPrev = !scrollOnly && currentPage > 1 && onPrev != null;
    final canNext = !scrollOnly && currentPage < maxPage && onNext != null;

    return Material(
      color: const Color(0xFFF5F3EE),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          HexaOp.pageGutter,
          4,
          HexaOp.pageGutter,
          8,
        ),
        child: Row(
          children: [
            if (!scrollOnly)
              IconButton(
                tooltip: 'Previous page',
                onPressed: canPrev ? onPrev : null,
                icon: const Icon(Icons.chevron_left_rounded),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Showing $showingCount of $totalCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!scrollOnly)
                    Text(
                      'Page $currentPage of $maxPage',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    )
                  else if (loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (showingCount < totalCount)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'Scroll for more',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            if (!scrollOnly)
              if (loading)
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Next page',
                  onPressed: canNext ? onNext : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
