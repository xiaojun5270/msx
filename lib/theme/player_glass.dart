import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../stores/ui_store.dart';
import 'theme.dart';

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
///
/// Two materials are available (设置 → 界面材质):
///  - liquid 液态玻璃: clear refractive lens, no body tint — samples and bends
///    the page behind it.
///  - frosted 毛玻璃: classic Gaussian frost — flat panel (no lens curvature,
///    no dispersion) with a stronger blur and a translucent veil.
LiquidGlassSettings playerGlassSettings(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  // Widget tests pump bare glass controls without providers; default to the
  // liquid material there instead of throwing.
  final ui = context.read<UIStore?>();
  final material = ui?.glassMaterial ?? GlassMaterial.liquid;
  if (material == GlassMaterial.frosted) {
    return LiquidGlassSettings(
      glassColor:
          dark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.42),
      bodyMode: GlassBodyMode.clear,
      blur: 22,
      thickness: 0,
      refractiveIndex: 1.0,
      saturation: 1,
      chromaticAberration: 0,
      lightIntensity: dark ? 0.3 : 0.22,
      glowIntensity: 0,
      shadowElevation: 0.2,
    );
  }
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

/// Current interface material for the calling context.
GlassMaterial appGlassMaterial(BuildContext context) =>
    context.read<UIStore>().glassMaterial;
