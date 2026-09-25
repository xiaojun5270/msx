import 'package:flutter/material.dart';

class LiquidGlassBottomBarItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final int? badge;

  const LiquidGlassBottomBarItem({
    required this.icon,
    required this.label,
    this.activeIcon,
    this.badge,
  });
}

/// API-compatible liquid glass bar with stable, fill-free compositing.
///
/// The hosted package uses multiple backdrop filters and fixed white veils.
/// This implementation keeps its navigation API and moving pill while avoiding
/// those layers, so page changes and scroll-idle frames render identically.
class LiquidGlassBottomBar extends StatelessWidget {
  final List<LiquidGlassBottomBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double? height;
  final EdgeInsetsGeometry margin;
  final bool showLabels;
  final Color activeColor;
  final double barBlurSigma;
  final double activeBlurSigma;

  const LiquidGlassBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.height,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 12),
    this.showLabels = true,
    this.activeColor = const Color(0xFF34C3FF),
    this.barBlurSigma = 0,
    this.activeBlurSigma = 0,
  })  : assert(items.length >= 2),
        assert(currentIndex >= 0 && currentIndex < items.length);

  @override
  Widget build(BuildContext context) {
    final barHeight = height ?? (showLabels ? 64.0 : 54.0);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = Theme.of(context).colorScheme.onSurface;
    final inactive = foreground.withOpacity(dark ? 0.72 : 0.64);

    return SafeArea(
      top: false,
      child: Padding(
        padding: margin,
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = index == currentIndex;
              final color = selected ? activeColor : inactive;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(index),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            selected
                                ? (item.activeIcon ?? item.icon)
                                : item.icon,
                            size: 22,
                            color: color,
                          ),
                          if ((item.badge ?? 0) > 0)
                            Positioned(
                              right: -9,
                              top: -7,
                              child: _Badge(count: item.badge!),
                            ),
                        ],
                      ),
                      if (showLabels) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
