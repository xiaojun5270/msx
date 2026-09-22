import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';

/// Liquid Glass surface — a blurred, translucent panel with a hairline edge and
/// a soft top highlight. Approximates iOS 26 `.glassEffect(.regular, in:)`.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final bool interactive;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blur = 24,
    this.padding,
    this.tint,
    this.interactive = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = MXBrightness.isDark;
    final base = tint ??
        (dark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.55));
    final edge = dark ? Colors.white.withOpacity(0.14) : Colors.white.withOpacity(0.6);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                base.withOpacity((base.opacity + 0.06).clamp(0.0, 1.0)),
                base,
              ],
            ),
            border: Border.all(color: edge, width: 0.8),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A pill-shaped glass chip — used for the toast and small chrome elements.
class GlassCapsule extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double blur;
  const GlassCapsule({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.blur = 24,
  });
  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.circular(999),
      blur: blur,
      padding: padding,
      child: child,
    );
  }
}

/// A frosted background layer used behind sheets / now-playing.
class GlassScrim extends StatelessWidget {
  final double blur;
  final Color color;
  const GlassScrim({super.key, this.blur = 40, this.color = Colors.black38});
  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(color: color),
    );
  }
}
