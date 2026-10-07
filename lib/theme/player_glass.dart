import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Shared, neutral material for the floating playback controls and dock.
/// Keep the tint subtle so custom wallpaper stays visible through the lens.
LiquidGlassSettings playerGlassSettings(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return LiquidGlassSettings(
    glassColor: dark ? const Color(0x12000000) : const Color(0x12FFFFFF),
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
