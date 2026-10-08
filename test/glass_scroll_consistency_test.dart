import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musix/views/glass_surfaces.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final contentCard in [true, false]) {
      testWidgets(
          '${contentCard ? 'profile/settings content' : 'outlined panels'} preserve wallpaper pixels at rest, during drag and after settling in $brightness',
          (tester) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() => LiquidGlassWidgets.initialize(
            enablePerformanceMonitor: false,
            warmUpMode: GlassWarmUpMode.never));
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final capture = GlobalKey();
        await tester.pumpWidget(LiquidGlassWidgets.wrap(
          brightnessResolver: Theme.maybeBrightnessOf,
          adaptiveQuality: true,
          adaptiveConfig: const GlassAdaptiveScopeConfig(
              minQuality: GlassQuality.standard,
              maxQuality: GlassQuality.standard,
              initialQuality: GlassQuality.standard),
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: RepaintBoundary(
                key: capture,
                child: Stack(children: [
                  const Positioned.fill(
                      child: CustomPaint(painter: _Wallpaper())),
                  RepaintBoundary(
                      child: ListView(
                          controller: controller,
                          padding: const EdgeInsets.all(20),
                          children: [
                        for (var i = 0; i < 12; i++)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: contentCard
                                  ? const MusicGlassPanel.card(
                                      child: SizedBox(
                                          height: 120, width: double.infinity))
                                  : const MusicGlassPanel(
                                      child: SizedBox(
                                          height: 120,
                                          width: double.infinity))),
                      ])),
                ])),
          ),
        ));
        await tester.pumpAndSettle();
        Future<Uint8List> pixels() async {
          final boundary = capture.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          return Uint8List.fromList(data!.buffer.asUint8List());
        }

        final before = await tester.runAsync(pixels);
        // A passing consistency check is insufficient if all three frames use
        // the wrong frosted material. Require the wallpaper's actual RGB too.
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(GlassContainer), findsNothing);
        // Move by exactly one row so the same glass geometry covers the same
        // fixed wallpaper pixels. This separates material changes from position.
        final drag = controller.position.drag(DragStartDetails(), () {});
        drag.update(DragUpdateDetails(
            delta: const Offset(0, -140),
            primaryDelta: -140,
            globalPosition: const Offset(180, 410)));
        await tester.pump();
        expect(controller.position.isScrollingNotifier.value, isTrue);
        expect(controller.offset, 140);
        final during = await tester.runAsync(pixels);
        drag.end(DragEndDetails(primaryVelocity: 0));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        expect(controller.position.isScrollingNotifier.value, isFalse);
        expect(controller.offset, 140);
        final after = await tester.runAsync(pixels);
        // Compare the centre of the first panel, excluding the list scrollbar,
        // clipped corners and anti-aliased rim.
        for (var y = 45; y < 115; y++) {
          for (var x = 65; x < 325; x++) {
            final offset = (y * 390 + x) * 4;
            final expectedColor =
                ((x ~/ 8) + (y ~/ 8)).isEven ? Colors.lightBlue : Colors.orange;
            final argb = expectedColor.toARGB32();
            final rgba = [
              (argb >> 16) & 255,
              (argb >> 8) & 255,
              argb & 255,
              255
            ];
            for (var channel = 0; channel < 4; channel++) {
              expect(before![offset + channel], rgba[channel]);
              expect(
                  (before[offset + channel] - during![offset + channel]).abs(),
                  lessThanOrEqualTo(2));
              expect(
                  (during[offset + channel] - after![offset + channel]).abs(),
                  lessThanOrEqualTo(2));
            }
          }
        }
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

class _Wallpaper extends CustomPainter {
  const _Wallpaper();
  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0; y < size.height; y += 8) {
      for (var x = 0; x < size.width; x += 8) {
        canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), y.toDouble(), 8, 8),
            Paint()
              ..color = ((x ~/ 8) + (y ~/ 8)).isEven
                  ? Colors.lightBlue
                  : Colors.orange);
      }
    }
  }

  @override
  bool shouldRepaint(_Wallpaper oldDelegate) => false;
}
