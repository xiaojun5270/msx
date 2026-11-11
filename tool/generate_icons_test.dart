// Icon generator harness — run explicitly with:
//   flutter test tool/generate_icons_test.dart
// Renders all launcher icon variants into Android mipmap dirs and the
// Flutter preview assets. Not part of the regular test suite.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/painting.dart' show Rect;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generate launcher icon variants', () async {
    final root = Directory.current.path;
    final outAssets = Directory('$root/assets/icons')
      ..createSync(recursive: true);

    const variants = <IconVariant>[
      IconVariant(
          'classic',
          [ui.Color(0xFF26E8FF), ui.Color(0xFFFF3F92), ui.Color(0xFFFFCF5A)],
          ui.Color(0xFF26E8FF),
          ui.Color(0xFF1E2B35)),
      IconVariant(
          'midnight',
          [ui.Color(0xFF4FA8FF), ui.Color(0xFF2E6BFF), ui.Color(0xFF7FD0FF)],
          ui.Color(0xFF4FA8FF),
          ui.Color(0xFF16222E)),
      IconVariant(
          'sunset',
          [ui.Color(0xFFFFCF5A), ui.Color(0xFFFF7A3C), ui.Color(0xFFFF4D6D)],
          ui.Color(0xFFFF9A3C),
          ui.Color(0xFF2B1D16)),
      IconVariant(
          'mint',
          [ui.Color(0xFF5CF2C7), ui.Color(0xFF2FC9A8), ui.Color(0xFFB8F5DC)],
          ui.Color(0xFF46E3B0),
          ui.Color(0xFF12291F)),
      IconVariant(
          'aurora',
          [ui.Color(0xFFB44CFF), ui.Color(0xFFFF4CD8), ui.Color(0xFF7FB2FF)],
          ui.Color(0xFFB44CFF),
          ui.Color(0xFF1D1630)),
      IconVariant(
          'cherry',
          [ui.Color(0xFFFF9AC2), ui.Color(0xFFFF5C8A), ui.Color(0xFFFFD3E0)],
          ui.Color(0xFFFF7FA9),
          ui.Color(0xFF2E1620)),
      IconVariant(
          'mono',
          [ui.Color(0xFFF5F5F5), ui.Color(0xFFC9C9C9), ui.Color(0xFFFFFFFF)],
          ui.Color(0xFFE8E8E8),
          ui.Color(0xFF14161A)),
      IconVariant(
          'lime',
          [ui.Color(0xFFD6FF4A), ui.Color(0xFF7BFF5C), ui.Color(0xFF4AE8FF)],
          ui.Color(0xFFA4FF4A),
          ui.Color(0xFF1A2612)),
    ];

    const mipmaps = <String, int>{
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };

    for (final v in variants) {
      final master = await renderIcon(v, 1024);
      // Android mipmap densities.
      for (final entry in mipmaps.entries) {
        final png = await scaleToPng(master, entry.value);
        final dir = Directory(
            '$root/android/app/src/main/res/mipmap-${entry.key}');
        dir.createSync(recursive: true);
        File('${dir.path}/ic_launcher_${v.id}.png').writeAsBytesSync(png);
      }
      // Flutter preview asset (grid picker).
      final preview = await scaleToPng(master, 256);
      File('${outAssets.path}/icon_${v.id}.png').writeAsBytesSync(preview);
      stdout.writeln('generated ${v.id}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class IconVariant {
  final String id;
  final List<ui.Color> ribbon; // [start, mid, end]
  final ui.Color accent; // ring + underline
  final ui.Color bgTint;

  const IconVariant(this.id, this.ribbon, this.accent, this.bgTint);
}

Future<ui.Image> renderIcon(IconVariant v, int size) async {
  const s = 1024.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(size / s);

  ui.Color withA(ui.Color c, double a) => c.withValues(alpha: a);

  // 1. Background radial gradient.
  final bgPaint = ui.Paint()
    ..shader = ui.Gradient.radial(
      const Offset(s * 0.34, s * 0.24),
      s * 0.82,
      [
        _shiftTowardWhite(v.bgTint, 0.12),
        _darken(v.bgTint, 0.55),
        const ui.Color(0xFF050507),
      ],
      const [0, 0.48, 1],
    );
  canvas.drawPaint(bgPaint);

  // 2. Vinyl disc.
  final vinylPaint = ui.Paint()
    ..shader = ui.Gradient.radial(
      const Offset(s * 0.5, s * 0.48),
      s * 0.55,
      const [
        ui.Color(0xFF262936),
        ui.Color(0xFF11131B),
        ui.Color(0xFF050508),
      ],
      const [0, 0.54, 1],
    );
  canvas.drawCircle(const Offset(512, 512), 386, vinylPaint);

  // 3. Accent ring.
  canvas.drawCircle(
    const Offset(512, 512),
    386,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = withA(v.accent, 0.16),
  );

  // 4. Groove circles.
  final grooves = <double>[302, 226, 151];
  final widths = <double>[9, 7, 5];
  for (var i = 0; i < grooves.length; i++) {
    canvas.drawCircle(
      const Offset(512, 512),
      grooves[i],
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = widths[i]
        ..color = withA(const ui.Color(0xFFF7F5FF), 0.075),
    );
  }

  // 5. Top-left shine crescent.
  final outer = ui.Path()
    ..addOval(Rect.fromCircle(center: const Offset(512, 512), radius: 350));
  final inner = ui.Path()
    ..addOval(Rect.fromCircle(center: const Offset(512, 560), radius: 350));
  final crescent =
      ui.Path.combine(ui.PathOperation.difference, outer, inner);
  canvas.drawPath(
    crescent,
    ui.Paint()
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.09)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 30),
  );

  // 6. Center hub.
  canvas.drawCircle(
      const Offset(512, 512), 118, ui.Paint()..color = const ui.Color(0xFF08090D));
  final hubPaint = ui.Paint()
    ..shader = ui.Gradient.linear(
      const Offset(196, 676),
      const Offset(828, 342),
      v.ribbon,
      const [0.0, 0.52, 1.0],
    );
  canvas.drawCircle(const Offset(512, 512), 82, hubPaint);
  canvas.drawCircle(
      const Offset(512, 512), 26, ui.Paint()..color = const ui.Color(0xFF07080C));

  // 7. Neon M ribbon.
  final mPath = ui.Path()
    ..moveTo(241, 640)
    ..lineTo(354, 383)
    ..lineTo(512, 652)
    ..lineTo(670, 383)
    ..lineTo(783, 640);

  // Glow layers (simulated softGlow filter) — solid tinted paints, blurred.
  ui.Paint glow(double width, ui.Color color, double sigma) => ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeWidth = width
    ..color = color
    ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
  canvas.drawPath(mPath, glow(150, withA(v.ribbon[1], 0.35), 26));
  canvas.drawPath(mPath, glow(126, withA(v.ribbon[0], 0.45), 20));

  final ribbonPaint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeWidth = 112
    ..shader = ui.Gradient.linear(
      const Offset(196, 676),
      const Offset(828, 342),
      v.ribbon,
      const [0.0, 0.52, 1.0],
    );
  canvas.drawPath(mPath, ribbonPaint);

  // Inner dark V detail.
  final vPath = ui.Path()
    ..moveTo(354, 383)
    ..lineTo(512, 652)
    ..lineTo(670, 383);
  canvas.drawPath(
    vPath,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..strokeWidth = 36
      ..color = withA(const ui.Color(0xFF06070B), 0.58),
  );

  // 8. Cyan underline with soft glow.
  final underline = ui.Path()
    ..moveTo(236, 728)
    ..cubicTo(386, 806, 597, 819, 772, 730);
  canvas.drawPath(
    underline,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 30
      ..color = withA(v.accent, 0.4)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14),
  );
  canvas.drawPath(
    underline,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 20
      ..color = v.accent,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

Future<Uint8List> scaleToPng(ui.Image master, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(size / master.width.toDouble());
  canvas.drawImage(master, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  final scaled = await picture.toImage(size, size);
  picture.dispose();
  final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
  scaled.dispose();
  return data!.buffer.asUint8List();
}

ui.Color _darken(ui.Color c, double amount) => ui.Color.fromARGB(
      (c.a * 255).round(),
      ((c.r * 255) * (1 - amount * 0.9)).round().clamp(0, 255),
      ((c.g * 255) * (1 - amount * 0.9)).round().clamp(0, 255),
      ((c.b * 255) * (1 - amount * 0.9)).round().clamp(0, 255),
    );

ui.Color _shiftTowardWhite(ui.Color c, double amount) => ui.Color.fromARGB(
      (c.a * 255).round(),
      ((c.r * 255) + (255 - c.r * 255) * amount).round().clamp(0, 255),
      ((c.g * 255) + (255 - c.g * 255) * amount).round().clamp(0, 255),
      ((c.b * 255) + (255 - c.b * 255) * amount).round().clamp(0, 255),
    );
