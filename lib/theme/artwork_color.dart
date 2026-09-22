import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/api_client.dart';
import '../api/auth_box.dart';
import 'theme.dart';

/// Extracts a muted hero background color from artwork.
/// Mirrors Swift `ArtworkColor` (CIAreaAverage → HSV clamp).
class ArtworkColor {
  static final Map<String, Color> _cache = {};

  static Future<Color> load(String? src, APIClient api) async {
    if (src == null || src.isEmpty) return MX.heroBase;
    if (_cache.containsKey(src)) return _cache[src]!;
    final url = api.absolute(src);
    if (url == null) return MX.heroBase;
    try {
      final headers = <String, String>{};
      final cookie = AuthBox.shared.combinedCookieHeader();
      if (cookie != null) headers['Cookie'] = cookie;
      final provider = CachedNetworkImageProvider(url.toString(), headers: headers);
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(64, 64),
        maximumColorCount: 8,
      );
      final base = palette.dominantColor?.color ?? MX.heroBase;
      final themed = _theme(base);
      _cache[src] = themed;
      return themed;
    } catch (_) {
      return MX.heroBase;
    }
  }

  /// Apply the same saturation/brightness clamp the Swift code uses so hero
  /// gradients stay dark and muted regardless of the source art.
  static Color _theme(Color c) {
    final hsv = HSVColor.fromColor(c);
    final v = hsv.value;
    final s = hsv.saturation;
    final sat = (s * 1.2).clamp(v > 0.75 ? 0.28 : 0.38, 1.0);
    final bri = (v > 0.72 ? 0.3 : v * 0.55).clamp(0.16, 0.44);
    return HSVColor.fromAHSV(1, hsv.hue, sat.toDouble(), bri.toDouble()).toColor();
  }
}

/// Decode a `data:image/...;base64,` URL into an image provider (avatars/QR).
ImageProvider? dataUrlImage(String dataUrl) {
  final marker = 'base64,';
  final idx = dataUrl.indexOf(marker);
  if (idx < 0) return null;
  try {
    final bytes = base64Decode(dataUrl.substring(idx + marker.length));
    return MemoryImage(bytes);
  } catch (_) {
    return null;
  }
}
