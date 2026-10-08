import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Resolve the same adaptive quality for navigation and page glass surfaces.
GlassQuality playerGlassQuality(BuildContext context,
    {GlassQuality requested = GlassQuality.premium}) {
  final ceiling = GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
  int rank(GlassQuality value) => switch (value) {
        GlassQuality.minimal => 0,
        GlassQuality.standard => 1,
        GlassQuality.premium => 2,
      };
  return ceiling != null && rank(ceiling) < rank(requested)
      ? ceiling
      : requested;
}

/// Shared, neutral material for the floating playback controls and dock.
/// No body tint: the lens samples the current page rather than a fixed fill.
LiquidGlassSettings playerGlassSettings(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return LiquidGlassSettings(
    glassColor: Colors.transparent,
    bodyMode: GlassBodyMode.clear,
    blur: 6,
    thickness: 24,
    refractiveIndex: 1.18,
    saturation: 1,
    chromaticAberration: 0.008,
    lightIntensity: dark ? 0.65 : 0.45,
    glowIntensity: 0.12,
    shadowElevation: 0.2,
  );
}
