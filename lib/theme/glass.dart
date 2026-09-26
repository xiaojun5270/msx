import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'theme.dart';

/// App-wide backdrop. A custom image is shown without any color veil so every
/// transparent surface reveals the source image unchanged.
class AppBackdrop extends StatelessWidget {
  final Widget child;
  final String? imageUrl;

  const AppBackdrop({super.key, required this.child, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final viewport = MediaQuery.sizeOf(context);
    final base = dark ? const Color(0xFF0B090D) : const Color(0xFFF1F4F7);
    // Neutral ink gradient only — no accent/teal tint. Keeping the accent out
    // of the shared backdrop stops the theme color from bleeding onto every
    // page; the accent still shows on deliberate chrome (hero, active tab,
    // glass tint, controls).
    final top = dark ? const Color(0xFF141019) : const Color(0xFFFBFCFD);
    final bottom = dark ? const Color(0xFF08070A) : const Color(0xFFEDF1F4);

    final background = Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: base,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.5, 1],
              colors: [top, base, bottom],
            ),
          ),
        ),
        if (imageUrl != null)
          CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            useOldImageOnUrlChange: true,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minWidth: viewport.width,
              maxWidth: viewport.width,
              minHeight: viewport.height,
              maxHeight: viewport.height,
              child: SizedBox.fromSize(size: viewport, child: background),
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
        child: _OptionalBackdropFilter(
          sigma: blur,
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

class _OptionalBackdropFilter extends StatelessWidget {
  final double sigma;
  final Widget child;

  const _OptionalBackdropFilter({required this.sigma, required this.child});

  @override
  Widget build(BuildContext context) {
    if (sigma <= 0) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
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
