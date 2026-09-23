import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'theme.dart';

/// App-wide backdrop with broad color refraction for glass surfaces to reveal.
/// The bands stay subtle so artwork and dense library content remain primary.
class AppBackdrop extends StatelessWidget {
  final Widget child;
  final String? imageUrl;

  const AppBackdrop({super.key, required this.child, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF0B090D) : const Color(0xFFF1F4F7);
    final warm = Color.alphaBlend(
      ThemeAccent.current.color.withOpacity(dark ? 0.14 : 0.10),
      dark ? const Color(0xFF171219) : const Color(0xFFFBFCFD),
    );
    final cool = Color.alphaBlend(
      const Color(0xFF39A88F).withOpacity(dark ? 0.10 : 0.07),
      dark ? const Color(0xFF0D1213) : const Color(0xFFF4F8F7),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: base,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0, 0.34, 0.7, 1],
              colors: [warm, base, cool, base],
            ),
          ),
        ),
        if (imageUrl != null)
          CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 320),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        if (imageUrl != null)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? [
                        const Color.fromRGBO(11, 9, 13, 0.58),
                        const Color.fromRGBO(11, 9, 13, 0.76),
                      ]
                    : [
                        const Color.fromRGBO(248, 250, 252, 0.62),
                        const Color.fromRGBO(241, 246, 247, 0.78),
                      ],
              ),
            ),
          ),
        child,
      ],
    );
  }
}

/// Liquid Glass surface — a blurred, translucent panel with a hairline edge and
/// a soft top highlight. Approximates iOS 26 `.glassEffect(.regular, in:)`.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final bool interactive;
  final bool showBorder;
  final bool showHighlight;
  final bool showShadow;
  final bool pureBlur;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blur = 24,
    this.padding,
    this.tint,
    this.interactive = false,
    this.showBorder = true,
    this.showHighlight = true,
    this.showShadow = true,
    this.pureBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = tint ??
        (dark
            ? Colors.white.withOpacity(0.075)
            : Colors.white.withOpacity(0.52));
    final edge =
        dark ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.78);
    final accent =
        ThemeAccent.current.color.withOpacity(interactive ? 0.12 : 0.035);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(dark ? 0.24 : 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: pureBlur
                    ? const [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.transparent,
                      ]
                    : [
                        base.withOpacity(
                            (base.opacity + 0.08).clamp(0.0, 1.0)),
                        base,
                        Color.alphaBlend(accent, base),
                      ],
              ),
              border: showBorder ? Border.all(color: edge, width: 0.8) : null,
            ),
            child: Stack(
              children: [
                child,
                if (showHighlight)
                  Positioned(
                    top: 0,
                    left: 14,
                    right: 14,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withOpacity(dark ? 0.24 : 0.72),
                            Colors.transparent,
                          ],
                        ),
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
}

/// Generic panel using the same blur, veil, and highlight treatment as
/// `liquid_glass_bottom_bar`, for non-tab surfaces such as the mini player.
class LiquidGlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;

  const LiquidGlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.blurSigma = 20,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Colors.white.withAlpha(10)),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withAlpha(28),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
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
