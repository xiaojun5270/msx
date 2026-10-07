import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
