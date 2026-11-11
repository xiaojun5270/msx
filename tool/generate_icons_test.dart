// Icon generator harness — run explicitly with:
//   flutter test tool/generate_icons_test.dart
// Renders all launcher icon variants into Android mipmap dirs and the
// Flutter preview assets, plus a contact sheet at icon_previews/.
// Not part of the regular test suite.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/painting.dart' show Rect;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generate launcher icon variants', () async {
    final root = Directory.current.path;
    final outAssets = Directory('$root/assets/icons')
      ..createSync(recursive: true);
    final outSheet = Directory('$root/icon_previews')
      ..createSync(recursive: true);

    const variants = <IconVariant>[
      // ---- Ribbon-M colorways (dark, neon) ----
      IconVariant('classic', 'ribbonM', true,
          [ui.Color(0xFF26E8FF), ui.Color(0xFFFF3F92), ui.Color(0xFFFFCF5A)],
          ui.Color(0xFF31465C), ui.Color(0xFF1A2836)),
      IconVariant('midnight', 'ribbonM', true,
          [ui.Color(0xFF7FC4FF), ui.Color(0xFF3D7BFF), ui.Color(0xFFBFE0FF)],
          ui.Color(0xFF14315E), ui.Color(0xFF081831)),
      // ---- Ribbon-M colorways (bright) ----
      IconVariant('sunset', 'ribbonM', false,
          [ui.Color(0xFFFFFFFF), ui.Color(0xFFFFE3C8), ui.Color(0xFFFFF4E6)],
          ui.Color(0xFFFFB868), ui.Color(0xFFFF6C4E)),
      IconVariant('mint', 'ribbonM', false,
          [ui.Color(0xFF0E9B72), ui.Color(0xFF0BC08D), ui.Color(0xFF067A58)],
          ui.Color(0xFFD9FBEA), ui.Color(0xFF7BE8C0)),
      IconVariant('aurora', 'ribbonM', false,
          [ui.Color(0xFFFFFFFF), ui.Color(0xFFFFD9F4), ui.Color(0xFFE8D4FF)],
          ui.Color(0xFF8A3BFF), ui.Color(0xFFC44CFF)),
      IconVariant('cherry', 'ribbonM', false,
          [ui.Color(0xFFD6336C), ui.Color(0xFFB01E55), ui.Color(0xFFFF6E9E)],
          ui.Color(0xFFFFC2D6), ui.Color(0xFFFF87AB)),
      IconVariant('mono', 'ribbonM', false,
          [ui.Color(0xFF2A2E37), ui.Color(0xFF4A4F5A), ui.Color(0xFF14161B)],
          ui.Color(0xFFF4F4F6), ui.Color(0xFFC9CCD3)),
      IconVariant('lime', 'ribbonM', false,
          [ui.Color(0xFF2E5A0A), ui.Color(0xFF3F7A0E), ui.Color(0xFF1F3D06)],
          ui.Color(0xFFE9FFA0), ui.Color(0xFFA8E84A)),
      // ---- New distinct designs ----
      IconVariant('wave', 'wave', false,
          [ui.Color(0xFF26E8FF), ui.Color(0xFFFF3F92)],
          ui.Color(0xFFFDFEFF), ui.Color(0xFFE2E9F5)),
      IconVariant('vinyl', 'vinyl', false,
          [ui.Color(0xFFFF6C4E), ui.Color(0xFF1A1A1E)],
          ui.Color(0xFFF7F0E4), ui.Color(0xFFE3D3B8)),
      IconVariant('headphones', 'headphones', true,
          [ui.Color(0xFF5AD0FF), ui.Color(0xFF7C6CFF)],
          ui.Color(0xFF232F4E), ui.Color(0xFF0F1526)),
      IconVariant('note', 'note', false,
          [ui.Color(0xFFFFFFFF), ui.Color(0xFF0B6B5E)],
          ui.Color(0xFF79E8CE), ui.Color(0xFF2BB3A0)),
      IconVariant('playglass', 'playglass', false,
          [ui.Color(0xFF2E7BFF), ui.Color(0xFF26E8FF)],
          ui.Color(0xFFE3F2FF), ui.Color(0xFF9CC8F5)),
      IconVariant('eq', 'eq', true,
          [ui.Color(0xFF26E8FF), ui.Color(0xFFFF3F92), ui.Color(0xFFFFCF5A)],
          ui.Color(0xFF2A2F42), ui.Color(0xFF3A415C)),
      // ---- Second batch: more instruments & retro gear ----
      IconVariant('cassette', 'cassette', false,
          [ui.Color(0xFFFF6C4E), ui.Color(0xFF2B2B31)],
          ui.Color(0xFFFFE8C9), ui.Color(0xFFFFC08A)),
      IconVariant('mic', 'mic', true,
          [ui.Color(0xFFE8EAF0), ui.Color(0xFFB48CFF)],
          ui.Color(0xFF2A1E4A), ui.Color(0xFF4A2B6E)),
      IconVariant('pick', 'pick', false,
          [ui.Color(0xFFFFCF5A), ui.Color(0xFFFF4D6D)],
          ui.Color(0xFF3A1B33), ui.Color(0xFF22101F)),
      IconVariant('piano', 'piano', true,
          [ui.Color(0xFFFBF8F1), ui.Color(0xFFE8B04B)],
          ui.Color(0xFF4A1E2E), ui.Color(0xFF2A0F1A)),
      IconVariant('speaker', 'speaker', false,
          [ui.Color(0xFFFFCF5A), ui.Color(0xFF26E8FF)],
          ui.Color(0xFFFF9A5C), ui.Color(0xFFFF4D6D)),
      IconVariant('cd', 'cd', false,
          [ui.Color(0xFF4AA8FF), ui.Color(0xFFFF6C8A)],
          ui.Color(0xFFEAF0F8), ui.Color(0xFFC3CCDB)),
      IconVariant('radio', 'radio', true,
          [ui.Color(0xFFF3EAD8), ui.Color(0xFF26E8FF)],
          ui.Color(0xFF2B3A55), ui.Color(0xFF161E2E)),
      IconVariant('liquid', 'liquid', false,
          [ui.Color(0xFF8A5CFF), ui.Color(0xFF26E8FF)],
          ui.Color(0xFFA8CBFF), ui.Color(0xFFFFC2E8)),
    ];

    const mipmaps = <String, int>{
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };

    final sheetTiles = <ui.Image>[];
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
      // Flutter preview asset (grid picker) + tile for the contact sheet.
      final preview = await scaleToPng(master, 256);
      File('${outAssets.path}/icon_${v.id}.png').writeAsBytesSync(preview);
      sheetTiles.add(await decodePng(preview));
      master.dispose();
      stdout.writeln('generated ${v.id}');
    }

    // Contact sheet: 4 columns, rounded-corner tiles on a neutral canvas.
    const cols = 4;
    const tile = 256;
    final rows = (sheetTiles.length + cols - 1) ~/ cols;
    final sheetRecorder = ui.PictureRecorder();
    final sheetCanvas = ui.Canvas(sheetRecorder);
    sheetCanvas.drawPaint(ui.Paint()..color = const ui.Color(0xFFECEEF2));
    for (var i = 0; i < sheetTiles.length; i++) {
      final x = (i % cols) * (tile + 24) + 24.0;
      final y = (i ~/ cols) * (tile + 24) + 24.0;
      sheetCanvas.save();
      sheetCanvas.clipRRect(ui.RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, tile.toDouble(), tile.toDouble()),
          const ui.Radius.circular(48)));
      sheetCanvas.drawImage(sheetTiles[i], ui.Offset(x, y), ui.Paint());
      sheetCanvas.restore();
      sheetTiles[i].dispose();
    }
    final sheetPic = sheetRecorder.endRecording();
    final sheetImg =
        await sheetPic.toImage(cols * (tile + 24) + 24, rows * (tile + 24) + 24);
    sheetPic.dispose();
    final sheetData = await sheetImg.toByteData(format: ui.ImageByteFormat.png);
    File('${outSheet.path}/preview_sheet.png')
        .writeAsBytesSync(sheetData!.buffer.asUint8List());
    sheetImg.dispose();
    stdout.writeln('contact sheet written');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class IconVariant {
  final String id;
  final String design; // ribbonM | wave | vinyl | headphones | note | playglass | eq
  final bool dark; // dark background (neon glow) vs bright background
  final List<ui.Color> accent;
  final ui.Color bgTop;
  final ui.Color bgBottom;

  const IconVariant(
      this.id, this.design, this.dark, this.accent, this.bgTop, this.bgBottom);
}

ui.Color withA(ui.Color c, double a) => ui.Color.fromARGB(
      (a * 255).round(),
      (c.r * 255).round(),
      (c.g * 255).round(),
      (c.b * 255).round(),
    );

Future<ui.Image> renderIcon(IconVariant v, int size) async {
  const s = 1024.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(size / s);

  drawBackground(canvas, v);
  switch (v.design) {
    case 'ribbonM':
      drawRibbonM(canvas, v);
      break;
    case 'wave':
      drawWave(canvas, v);
      break;
    case 'vinyl':
      drawVinyl(canvas, v);
      break;
    case 'headphones':
      drawHeadphones(canvas, v);
      break;
    case 'note':
      drawNote(canvas, v);
      break;
    case 'playglass':
      drawPlayGlass(canvas, v);
      break;
    case 'eq':
      drawEq(canvas, v);
      break;
    case 'cassette':
      drawCassette(canvas, v);
      break;
    case 'mic':
      drawMic(canvas, v);
      break;
    case 'pick':
      drawPick(canvas, v);
      break;
    case 'piano':
      drawPiano(canvas, v);
      break;
    case 'speaker':
      drawSpeaker(canvas, v);
      break;
    case 'cd':
      drawCd(canvas, v);
      break;
    case 'radio':
      drawRadio(canvas, v);
      break;
    case 'liquid':
      drawLiquid(canvas, v);
      break;
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

void drawBackground(ui.Canvas canvas, IconVariant v) {
  const s = 1024.0;
  // Vertical gradient base — always tinted, never near-black.
  canvas.drawPaint(ui.Paint()
    ..shader = ui.Gradient.linear(
      ui.Offset.zero,
      const Offset(0, s),
      [v.bgTop, v.bgBottom],
      const [0, 1],
    ));
  // Two soft accent glow blobs for depth.
  canvas.drawCircle(
    const Offset(s * 0.22, s * 0.18),
    s * 0.42,
    ui.Paint()
      ..color = withA(v.accent.first, v.dark ? 0.22 : 0.30)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 60),
  );
  canvas.drawCircle(
    const Offset(s * 0.84, s * 0.86),
    s * 0.44,
    ui.Paint()
      ..color = withA(v.accent.last, v.dark ? 0.20 : 0.26)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 60),
  );
}

/// The classic neon "M" ribbon, sized to fill the frame (no vinyl disc).
void drawRibbonM(ui.Canvas canvas, IconVariant v) {
  final mPath = ui.Path()
    ..moveTo(150, 690)
    ..lineTo(318, 342)
    ..lineTo(512, 684)
    ..lineTo(706, 342)
    ..lineTo(874, 690);

  ui.Paint glow(double width, ui.Color color, double sigma) => ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeWidth = width
    ..color = color
    ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);

  final glowTint = v.dark ? v.accent[1] : const ui.Color(0xFFFFFFFF);
  canvas.drawPath(mPath, glow(150, withA(glowTint, v.dark ? 0.35 : 0.55), 26));
  canvas.drawPath(mPath, glow(120, withA(v.accent[0], v.dark ? 0.45 : 0.40), 20));

  final ribbonPaint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeWidth = 116
    ..shader = ui.Gradient.linear(
      const Offset(150, 690),
      const Offset(874, 342),
      v.accent,
      const [0.0, 0.5, 1.0],
    );
  canvas.drawPath(mPath, ribbonPaint);

  if (v.dark) {
    // Inner dark V detail — only reads well on bright ribbons.
    final vPath = ui.Path()
      ..moveTo(318, 342)
      ..lineTo(512, 684)
      ..lineTo(706, 342);
    canvas.drawPath(
      vPath,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..strokeWidth = 34
        ..color = withA(const ui.Color(0xFF06070B), 0.55),
    );
  }

  // Underline sweep.
  final underline = ui.Path()
    ..moveTo(220, 792)
    ..cubicTo(380, 862, 640, 866, 804, 794);
  canvas.drawPath(
    underline,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 24
      ..color = withA(v.dark ? v.accent[0] : v.accent[1], 0.85)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
  );
  canvas.drawPath(
    underline,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 18
      ..color = v.dark ? v.accent[0] : v.accent[1],
  );
}

/// Colorful waveform bars on a light background.
void drawWave(ui.Canvas canvas, IconVariant v) {
  const s = 1024.0;
  const barColors = <ui.Color>[
    ui.Color(0xFF26C9E8),
    ui.Color(0xFF7A6CFF),
    ui.Color(0xFFFF3F92),
    ui.Color(0xFFFF7A3C),
    ui.Color(0xFFFFB43C),
  ];
  const heights = <double>[340, 520, 660, 460, 320];
  for (var i = 0; i < 5; i++) {
    final cx = s / 2 + (i - 2) * 150.0;
    final h = heights[i];
    final rect = Rect.fromLTWH(cx - 39, s / 2 - h / 2, 78, h);
    final rrect =
        ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(39));
    // Soft glow behind each bar.
    canvas.drawRRect(
      rrect,
      ui.Paint()
        ..color = withA(barColors[i], 0.45)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 24),
    );
    canvas.drawRRect(
      rrect,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          Offset(rect.left, rect.top),
          Offset(rect.left, rect.bottom),
          [
            barColors[i],
            withA(barColors[i], 0.75),
          ],
          const [0, 1],
        ),
    );
  }
}

/// Retro vinyl disc with a tonearm on a cream background.
void drawVinyl(ui.Canvas canvas, IconVariant v) {
  const discC = ui.Color(0xFF1A1A1E);
  const label = ui.Color(0xFFFF6C4E);
  const cream = ui.Color(0xFFF7F0E4);

  // Disc.
  const discCenter = Offset(452, 548);
  canvas.drawCircle(
    discCenter,
    330,
    ui.Paint()
      ..shader = ui.Gradient.radial(
        discCenter,
        330,
        const [ui.Color(0xFF2A2A31), discC, ui.Color(0xFF0C0C0F)],
        const [0, 0.55, 1],
      ),
  );
  // Grooves.
  for (final r in <double>[268, 216, 168, 232, 190]) {
    canvas.drawCircle(
      discCenter,
      r,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = withA(const ui.Color(0xFFFFFFFF), 0.08),
    );
  }
  // Specular highlight.
  canvas.drawArc(
    Rect.fromCircle(center: discCenter, radius: 300),
    -2.4,
    0.9,
    false,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 26
      ..strokeCap = ui.StrokeCap.round
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.22)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12),
  );
  // Label + spindle.
  canvas.drawCircle(discCenter, 118, ui.Paint()..color = label);
  canvas.drawCircle(
    discCenter,
    118,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = withA(const ui.Color(0xFF000000), 0.18),
  );
  canvas.drawCircle(discCenter, 20, ui.Paint()..color = cream);

  // Tonearm: pivot top-right, arm reaching onto the disc.
  const pivot = Offset(806, 232);
  canvas.drawCircle(pivot, 58, ui.Paint()..color = const ui.Color(0xFF2B2B31));
  canvas.drawCircle(
    pivot,
    58,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.25),
  );
  canvas.drawCircle(pivot, 20, ui.Paint()..color = label);
  canvas.drawCircle(
    pivot,
    20,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = cream,
  );
  final arm = ui.Path()
    ..moveTo(pivot.dx - 34, pivot.dy + 34)
    ..lineTo(560, 610);
  canvas.drawPath(
    arm,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 26
      ..color = const ui.Color(0xFF3A3A42),
  );
  // Headshell.
  canvas.save();
  canvas.translate(560, 610);
  canvas.rotate(0.82);
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(-30, -14, 96, 52), const ui.Radius.circular(14)),
    ui.Paint()..color = const ui.Color(0xFF2B2B31),
  );
  canvas.restore();
}

/// Neon headphones on a deep navy background.
void drawHeadphones(ui.Canvas canvas, IconVariant v) {
  final bandPaint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeWidth = 74
    ..shader = ui.Gradient.linear(
      const Offset(240, 340),
      const Offset(784, 340),
      [v.accent[0], v.accent[1]],
      const [0, 1],
    );

  // Headband arc (top half).
  canvas.drawArc(
    Rect.fromCircle(center: const Offset(512, 596), radius: 272),
    math.pi,
    math.pi,
    false,
    bandPaint,
  );
  // Glow echo of the band.
  canvas.drawArc(
    Rect.fromCircle(center: const Offset(512, 596), radius: 272),
    math.pi,
    math.pi,
    false,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 110
      ..color = withA(v.accent[0], 0.25)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 26),
  );
  // Redraw crisp band over the glow.
  canvas.drawArc(
    Rect.fromCircle(center: const Offset(512, 596), radius: 272),
    math.pi,
    math.pi,
    false,
    bandPaint,
  );

  // Ear cups.
  for (final cx in <double>[240.0, 784.0]) {
    final rect = Rect.fromLTWH(cx - 78, 560, 156, 220);
    final rrect =
        ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(64));
    canvas.drawRRect(
      rrect,
      ui.Paint()
        ..color = withA(v.accent[1], 0.35)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 22),
    );
    canvas.drawRRect(
      rrect,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          Offset(rect.left, rect.top),
          Offset(rect.right, rect.bottom),
          [v.accent[0], v.accent[1]],
          const [0, 1],
        ),
    );
    // Cushion detail.
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 42, 596, 84, 148),
          const ui.Radius.circular(38)),
      ui.Paint()..color = withA(const ui.Color(0xFF0B1020), 0.55),
    );
  }

  // Sound waves under the cups.
  for (var i = 1; i <= 2; i++) {
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(512, 596), radius: 340 + i * 56),
      -0.62,
      1.24,
      false,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = 14
        ..color = withA(v.accent[0], 0.5 / i),
    );
  }
}

/// Beamed eighth notes on a fresh teal background.
void drawNote(ui.Canvas canvas, IconVariant v) {
  final white = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
  final shadow = ui.Paint()
    ..color = withA(const ui.Color(0xFF06423A), 0.35)
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18);

  // Whole-glyph soft shadow pass.
  canvas.save();
  canvas.translate(0, 16);
  _drawNoteGlyph(canvas, shadow);
  canvas.restore();

  _drawNoteGlyph(canvas, white);

  // Sparkle accents.
  for (final p in <Offset>[
    const Offset(214, 268),
    const Offset(806, 356),
    const Offset(756, 750),
  ]) {
    canvas.drawCircle(p, 14, white);
    canvas.drawCircle(
      p,
      30,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = withA(const ui.Color(0xFFFFFFFF), 0.55),
    );
  }
}

void _drawNoteGlyph(ui.Canvas canvas, ui.Paint paint) {
  // Note heads (rotated ellipses).
  for (final spec in <List<double>>[
    [356, 686, -0.32],
    [628, 646, -0.32],
  ]) {
    canvas.save();
    canvas.translate(spec[0], spec[1]);
    canvas.rotate(spec[2]);
    canvas.drawOval(
        Rect.fromCenter(center: ui.Offset.zero, width: 188, height: 136),
        paint);
    canvas.restore();
  }
  // Stems.
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(424, 350, 30, 340), const ui.Radius.circular(15)),
    paint,
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(696, 310, 30, 340), const ui.Radius.circular(15)),
    paint,
  );
  // Beam.
  final beam = ui.Path()
    ..moveTo(424, 350)
    ..lineTo(726, 310)
    ..lineTo(726, 380)
    ..lineTo(424, 420)
    ..close();
  canvas.drawPath(beam, paint);
}

/// Liquid-glass play button — frosted disc with a gradient triangle.
void drawPlayGlass(ui.Canvas canvas, IconVariant v) {
  const center = Offset(512, 512);

  // Frosted glass disc.
  canvas.drawCircle(
    center,
    306,
    ui.Paint()
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.35)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
  );
  canvas.drawCircle(
    center,
    306,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 14
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.9),
  );
  // Glass highlight arc.
  canvas.drawArc(
    Rect.fromCircle(center: center, radius: 268),
    -2.5,
    1.0,
    false,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 30
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.85)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14),
  );

  // Play triangle with rounded corners (fill + fat round-join stroke).
  final tri = ui.Path()
    ..moveTo(438, 372)
    ..lineTo(438, 652)
    ..lineTo(672, 512)
    ..close();
  final triShader = ui.Gradient.linear(
    const Offset(438, 372),
    const Offset(672, 652),
    [v.accent[0], v.accent[1]],
    const [0, 1],
  );
  // Soft colored glow behind the triangle.
  canvas.drawPath(
    tri,
    ui.Paint()
      ..color = withA(v.accent[0], 0.4)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 30),
  );
  canvas.drawPath(tri, ui.Paint()..shader = triShader);
  canvas.drawPath(
    tri,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..strokeWidth = 44
      ..shader = triShader,
  );
  // Fill the stroke hollows back in.
  canvas.drawPath(tri, ui.Paint()..shader = triShader);
}

/// Three vertical equalizer sliders with colored knobs.
void drawEq(ui.Canvas canvas, IconVariant v) {
  const xs = <double>[340, 512, 684];
  const knobYs = <double>[372, 636, 300];

  for (var i = 0; i < 3; i++) {
    final cx = xs[i];
    final track = ui.RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 27, 224, 54, 576),
        const ui.Radius.circular(27));
    canvas.drawRRect(track, ui.Paint()..color = withA(const ui.Color(0xFFFFFFFF), 0.16));

    final ky = knobYs[i];
    // Filled segment above the knob.
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 27, 224, 54, ky - 224),
          const ui.Radius.circular(27)),
      ui.Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - 27, 224),
          Offset(cx + 27, ky),
          [v.accent[i], withA(v.accent[i], 0.7)],
          const [0, 1],
        ),
    );
    // Knob.
    canvas.drawCircle(
      Offset(cx, ky),
      42,
      ui.Paint()
        ..color = withA(v.accent[i], 0.4)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18),
    );
    canvas.drawCircle(Offset(cx, ky), 42, ui.Paint()..color = v.accent[i]);
    canvas.drawCircle(
      Offset(cx, ky),
      42,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = withA(const ui.Color(0xFFFFFFFF), 0.85),
    );
    canvas.drawCircle(
      Offset(cx, ky),
      14,
      ui.Paint()..color = withA(const ui.Color(0xFFFFFFFF), 0.9),
    );
  }
}

/// Retro cassette tape — colored label, twin reels in a cream window.
void drawCassette(ui.Canvas canvas, IconVariant v) {
  const cream = ui.Color(0xFFF6EEDF);
  final body = ui.RRect.fromRectAndRadius(
      const Rect.fromLTWH(112, 300, 800, 430), const ui.Radius.circular(70));
  canvas.drawRRect(body, ui.Paint()..color = const ui.Color(0xFF23242B));
  canvas.drawRRect(
    body,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = withA(cream, 0.20),
  );

  // Colored label strip.
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(150, 334, 724, 94), const ui.Radius.circular(26)),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const Offset(150, 334),
        const Offset(874, 428),
        [v.accent[0], withA(v.accent[0], 0.55)],
        const [0, 1],
      ),
  );
  // Label holes.
  canvas.drawCircle(const Offset(204, 381), 14, ui.Paint()..color = cream);
  canvas.drawCircle(const Offset(820, 381), 14, ui.Paint()..color = cream);

  // Window + reels.
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(184, 452, 656, 176), const ui.Radius.circular(88)),
    ui.Paint()..color = cream,
  );
  for (final cx in <double>[352, 672]) {
    canvas.drawCircle(
        Offset(cx, 540), 74, ui.Paint()..color = const ui.Color(0xFF2B2B31));
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawLine(
        Offset(cx + math.cos(a) * 30, 540 + math.sin(a) * 30),
        Offset(cx + math.cos(a) * 62, 540 + math.sin(a) * 62),
        ui.Paint()
          ..strokeWidth = 10
          ..strokeCap = ui.StrokeCap.round
          ..color = cream,
      );
    }
    canvas.drawCircle(Offset(cx, 540), 26, ui.Paint()..color = cream);
  }

  // Head opening.
  final head = ui.Path()
    ..moveTo(360, 668)
    ..lineTo(664, 668)
    ..lineTo(628, 716)
    ..lineTo(396, 716)
    ..close();
  canvas.drawPath(head, ui.Paint()..color = withA(cream, 0.92));

  // Screws.
  for (final p in <Offset>[
    const Offset(168, 352),
    const Offset(856, 352),
    const Offset(168, 678),
    const Offset(856, 678),
  ]) {
    canvas.drawCircle(p, 13, ui.Paint()..color = withA(cream, 0.45));
  }
}

/// Studio microphone — metallic capsule with grille, purple backdrop.
void drawMic(ui.Canvas canvas, IconVariant v) {
  // Handle + base first (behind capsule).
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(466, 460, 92, 270), const ui.Radius.circular(46)),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const Offset(466, 460),
        const Offset(558, 730),
        [const ui.Color(0xFF9AA1B2), const ui.Color(0xFF565C6E)],
        const [0, 1],
      ),
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(392, 706, 240, 56), const ui.Radius.circular(28)),
    ui.Paint()..color = const ui.Color(0xFF3A3F52),
  );

  final cap = ui.RRect.fromRectAndRadius(
      const Rect.fromLTWH(382, 150, 260, 360), const ui.Radius.circular(130));
  // Glow behind the capsule.
  canvas.drawRRect(
    cap,
    ui.Paint()
      ..color = withA(v.accent[1], 0.45)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 46),
  );
  canvas.drawRRect(
    cap,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const Offset(382, 150),
        const Offset(642, 510),
        const [
          ui.Color(0xFFF6F8FC),
          ui.Color(0xFFAEB5C6),
          ui.Color(0xFFE9ECF4),
        ],
        const [0, 0.55, 1],
      ),
  );
  // Grille lines clipped to the capsule.
  canvas.save();
  canvas.clipRRect(cap);
  for (var y = 196.0; y < 500; y += 28) {
    canvas.drawLine(
      const Offset(382, 0).translate(0, y),
      const Offset(642, 0).translate(0, y),
      ui.Paint()
        ..strokeWidth = 6
        ..color = withA(const ui.Color(0xFF565C6E), 0.42),
    );
  }
  // Violet band across the capsule base.
  canvas.drawRect(
    const Rect.fromLTWH(382, 452, 260, 40),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const Offset(382, 452),
        const Offset(642, 492),
        [v.accent[1], withA(v.accent[1], 0.7)],
        const [0, 1],
      ),
  );
  canvas.restore();
  canvas.drawRRect(
    cap,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.65),
  );
}

/// Guitar pick over glowing strings.
void drawPick(ui.Canvas canvas, IconVariant v) {
  // Strings behind, well clear of the pick silhouette.
  for (var i = 0; i < 3; i++) {
    final y = 348.0 + i * 130;
    canvas.drawLine(
      Offset(140, y),
      Offset(884, y),
      ui.Paint()
        ..strokeWidth = 10
        ..color = withA(const ui.Color(0xFFFFFFFF), 0.45),
    );
  }

  final pick = ui.Path()
    ..moveTo(410, 330)
    ..quadraticBezierTo(512, 300, 614, 330)
    ..quadraticBezierTo(732, 330, 688, 431)
    ..quadraticBezierTo(648, 610, 540, 766)
    ..quadraticBezierTo(512, 830, 484, 766)
    ..quadraticBezierTo(376, 610, 336, 431)
    ..quadraticBezierTo(292, 330, 410, 330)
    ..close();

  canvas.save();
  canvas.translate(512, 535);
  canvas.rotate(-0.12);
  canvas.translate(-512, -535);

  canvas.drawPath(
    pick,
    ui.Paint()
      ..color = withA(v.accent[1], 0.55)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 40),
  );
  canvas.drawPath(
    pick,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const Offset(298, 258),
        const Offset(726, 812),
        [v.accent[0], v.accent[1]],
        const [0, 1],
      ),
  );
  canvas.drawPath(
    pick,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.6),
  );
  // Gloss crescent + grip dots.
  canvas.drawArc(
    Rect.fromCircle(center: const Offset(512, 500), radius: 160),
    -2.5,
    0.8,
    false,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 30
      ..strokeCap = ui.StrokeCap.round
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.5)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14),
  );
  for (final dy in <double>[-6, 44, 94]) {
    canvas.drawCircle(
      Offset(512, 470 + dy),
      16,
      ui.Paint()..color = withA(const ui.Color(0xFFFFFFFF), 0.45),
    );
  }
  canvas.restore();
}

/// Piano keyboard — five white keys with four black keys.
void drawPiano(ui.Canvas canvas, IconVariant v) {
  const x0 = 172.0;
  const w = 136.0;
  // Keyboard shadow.
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(x0, 812, 676, 56), const ui.Radius.circular(26)),
    ui.Paint()
      ..color = withA(const ui.Color(0xFF000000), 0.45)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 22),
  );

  final whitePaint = ui.Paint()
    ..shader = ui.Gradient.linear(
      const Offset(0, 300),
      const Offset(0, 820),
      [const ui.Color(0xFFFFFDF8), const ui.Color(0xFFE8E0CE)],
      const [0, 1],
    );
  for (var i = 0; i < 5; i++) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
          Rect.fromLTWH(x0 + i * w, 300, w - 8, 520),
          const ui.Radius.circular(20)),
      whitePaint,
    );
  }
  // Black keys straddle white-key boundaries.
  final blackPaint = ui.Paint()
    ..shader = ui.Gradient.linear(
      const Offset(0, 300),
      const Offset(0, 620),
      [const ui.Color(0xFF2B2B36), const ui.Color(0xFF0E0E14)],
      const [0, 1],
    );
  for (var i = 1; i < 5; i++) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
          Rect.fromLTWH(x0 + i * w - 46, 300, 84, 318),
          const ui.Radius.circular(16)),
      blackPaint,
    );
    // Top edge highlight on each black key.
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
          Rect.fromLTWH(x0 + i * w - 40, 312, 72, 12),
          const ui.Radius.circular(6)),
      ui.Paint()..color = withA(v.accent[1], 0.35),
    );
  }
}

/// Subwoofer — dark cone with colored dust cap on a warm backdrop.
void drawSpeaker(ui.Canvas canvas, IconVariant v) {
  const c = Offset(512, 512);
  canvas.drawCircle(c, 350, ui.Paint()..color = const ui.Color(0xFF1B1C23));
  canvas.drawCircle(
    c,
    350,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 18
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.20),
  );
  // Cone.
  canvas.drawCircle(
    c,
    296,
    ui.Paint()
      ..shader = ui.Gradient.radial(
        c,
        296,
        const [
          ui.Color(0xFF525869),
          ui.Color(0xFF23252E),
          ui.Color(0xFF101118),
        ],
        const [0, 0.62, 1],
      ),
  );
  for (final r in <double>[252, 212, 172]) {
    canvas.drawCircle(
      c,
      r,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = withA(const ui.Color(0xFFFFFFFF), 0.06),
    );
  }
  // Dust cap.
  canvas.drawCircle(
    c,
    116,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const Offset(396, 396),
        const Offset(628, 628),
        [v.accent[0], v.accent[1]],
        const [0, 1],
      ),
  );
  canvas.drawCircle(
    c,
    116,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.35),
  );
  // Screws.
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4 + 0.39;
    canvas.drawCircle(
      Offset(c.dx + math.cos(a) * 326, c.dy + math.sin(a) * 326),
      13,
      ui.Paint()..color = withA(const ui.Color(0xFFFFFFFF), 0.38),
    );
  }
  // Specular arc.
  canvas.drawArc(
    Rect.fromCircle(center: c, radius: 308),
    -2.7,
    0.9,
    false,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 26
      ..strokeCap = ui.StrokeCap.round
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.16)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12),
  );
}

/// Iridescent CD with rainbow sweep and center hole.
void drawCd(ui.Canvas canvas, IconVariant v) {
  const c = Offset(512, 512);
  canvas.drawCircle(
    c,
    344,
    ui.Paint()
      ..shader = ui.Gradient.radial(
        c,
        344,
        const [
          ui.Color(0xFFF9FBFF),
          ui.Color(0xFFD2D9E5),
          ui.Color(0xFFF0F3F9),
        ],
        const [0, 0.72, 1],
      ),
  );
  canvas.save();
  canvas.clipPath(ui.Path()..addOval(Rect.fromCircle(center: c, radius: 344)));
  canvas.drawCircle(
    c,
    344,
    ui.Paint()
      ..shader = ui.Gradient.sweep(
        c,
        const [
          ui.Color(0x00FFFFFF),
          ui.Color(0x66FF6C8A),
          ui.Color(0x664AA8FF),
          ui.Color(0x66FFE14A),
          ui.Color(0x664AFFB0),
          ui.Color(0x668A5CFF),
          ui.Color(0x00FFFFFF),
        ],
        const [0, 0.16, 0.33, 0.5, 0.66, 0.83, 1],
      ),
  );
  canvas.restore();
  // Specular arc.
  canvas.drawArc(
    Rect.fromCircle(center: c, radius: 300),
    -2.8,
    0.8,
    false,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = ui.StrokeCap.round
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.7)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
  );
  // Rim.
  canvas.drawCircle(
    c,
    344,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.85),
  );
  // Center hole.
  canvas.drawCircle(c, 96, ui.Paint()..color = v.bgTop);
  canvas.drawCircle(
    c,
    96,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.9),
  );
}

/// Retro radio — grill dots, cream dial with a red needle, twin knobs.
void drawRadio(ui.Canvas canvas, IconVariant v) {
  const cream = ui.Color(0xFFF3EAD8);
  // Antenna.
  canvas.drawLine(
    const Offset(826, 258),
    const Offset(942, 96),
    ui.Paint()
      ..strokeWidth = 14
      ..strokeCap = ui.StrokeCap.round
      ..color = withA(cream, 0.85),
  );
  // Body.
  final body = ui.RRect.fromRectAndRadius(
      const Rect.fromLTWH(116, 236, 792, 552), const ui.Radius.circular(66));
  canvas.drawRRect(
    body,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const Offset(116, 236),
        const Offset(908, 788),
        [const ui.Color(0xFF38486A), const ui.Color(0xFF18202F)],
        const [0, 1],
      ),
  );
  canvas.drawRRect(
    body,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.12),
  );
  // Speaker grill.
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(164, 300, 380, 424), const ui.Radius.circular(42)),
    ui.Paint()..color = const ui.Color(0xFF0E1420),
  );
  for (var r = 0; r < 7; r++) {
    for (var col = 0; col < 6; col++) {
      canvas.drawCircle(
        Offset(208.0 + col * 62, 348.0 + r * 58),
        13,
        ui.Paint()..color = withA(cream, 0.55),
      );
    }
  }
  // Dial panel.
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const Rect.fromLTWH(578, 300, 296, 172), const ui.Radius.circular(26)),
    ui.Paint()..color = cream,
  );
  for (var i = 0; i < 10; i++) {
    final x = 604.0 + i * 28;
    canvas.drawLine(
      Offset(x, 330),
      Offset(x, 330 + (i % 2 == 0 ? 30 : 18)),
      ui.Paint()
        ..strokeWidth = 5
        ..color = withA(const ui.Color(0xFF8A7F6B), 0.75),
    );
  }
  canvas.drawLine(
    const Offset(756, 322),
    const Offset(756, 406),
    ui.Paint()
      ..strokeWidth = 9
      ..strokeCap = ui.StrokeCap.round
      ..color = const ui.Color(0xFFE5402F),
  );
  // Knobs.
  for (final k in <Offset>[const Offset(676, 640), const Offset(806, 640)]) {
    canvas.drawCircle(k, 56, ui.Paint()..color = const ui.Color(0xFF2A3448));
    canvas.drawCircle(
      k,
      56,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = withA(cream, 0.8),
    );
    canvas.drawLine(
      Offset(k.dx, k.dy - 34),
      Offset(k.dx, k.dy - 8),
      ui.Paint()
        ..strokeWidth = 9
        ..strokeCap = ui.StrokeCap.round
        ..color = withA(cream, 0.85),
    );
  }
  // Power LED.
  canvas.drawCircle(const Offset(844, 372), 12,
      ui.Paint()..color = withA(v.accent[1], 0.95));
}

/// Liquid-glass abstraction — blurred color blobs behind frosted discs.
void drawLiquid(ui.Canvas canvas, IconVariant v) {
  canvas.drawCircle(
    const Offset(330, 340),
    220,
    ui.Paint()
      ..color = withA(v.accent[0], 0.60)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 46),
  );
  canvas.drawCircle(
    const Offset(720, 720),
    240,
    ui.Paint()
      ..color = withA(const ui.Color(0xFFFF5C8A), 0.55)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 50),
  );
  canvas.drawCircle(
    const Offset(798, 300),
    160,
    ui.Paint()
      ..color = withA(v.accent[1], 0.60)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 42),
  );

  // Frosted disc 1.
  canvas.drawCircle(
    const Offset(452, 470),
    236,
    ui.Paint()
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.24)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
  );
  canvas.drawCircle(
    const Offset(452, 470),
    236,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.8),
  );
  canvas.drawArc(
    Rect.fromCircle(center: const Offset(452, 470), radius: 200),
    -2.7,
    0.85,
    false,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = ui.StrokeCap.round
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.75)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12),
  );

  // Frosted disc 2 (overlapping).
  canvas.drawCircle(
    const Offset(668, 618),
    168,
    ui.Paint()
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.20)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
  );
  canvas.drawCircle(
    const Offset(668, 618),
    168,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = withA(const ui.Color(0xFFFFFFFF), 0.7),
  );

  // Floating bubbles.
  for (final b in <List<double>>[
    [700, 268, 40],
    [300, 760, 30],
    [760, 520, 22],
  ]) {
    canvas.drawCircle(Offset(b[0], b[1]), b[2],
        ui.Paint()..color = withA(const ui.Color(0xFFFFFFFF), 0.55));
  }
}

Future<ui.Image> decodePng(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
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
