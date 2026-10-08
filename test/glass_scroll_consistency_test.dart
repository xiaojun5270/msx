import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musix/theme/theme.dart';
import 'package:musix/views/glass_surfaces.dart';
import 'package:musix/views/shell.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final quality in [GlassQuality.minimal, GlassQuality.standard]) {
      testWidgets(
          'cards match navigation glass at rest, during scroll and after shader loss in $brightness at $quality',
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
        var useMaterial3 = true;
        late StateSetter update;
        final list = RepaintBoundary(
          key: GlobalKey(),
          child: ListView(
            addRepaintBoundaries: false,
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              for (var i = 0; i < 12; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: MusicGlassPanel.card(
                      radius: 30,
                      child: SizedBox(height: 60, width: double.infinity)),
                ),
            ],
          ),
        );
        await tester.pumpWidget(LiquidGlassWidgets.wrap(
          brightnessResolver: Theme.maybeBrightnessOf,
          adaptiveQuality: true,
          adaptiveConfig: GlassAdaptiveScopeConfig(
              minQuality: quality,
              maxQuality: quality,
              initialQuality: quality),
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: StatefulBuilder(builder: (context, setState) {
              update = setState;
              return Theme(
                data: ThemeData(
                    brightness: brightness, useMaterial3: useMaterial3),
                child: RepaintBoundary(
                  key: capture,
                  child: Stack(children: [
                    const Positioned.fill(
                        child: CustomPaint(
                            painter: _Wallpaper(verticalOnly: true))),
                    LiquidGlassScope(
                      child: Stack(children: [
                        // Compare both materials over bare wallpaper, avoiding
                        // a second glass card beneath the bar's sample point.
                        Positioned.fill(
                          bottom: 100,
                          child: GlassBackgroundSource(child: list),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LiquidDock(
                            current: AppTab.home,
                            order: AppTab.values,
                            onSelect: (_) {},
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              );
            }),
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

        final before = (await tester.runAsync(pixels))!;
        final drag = controller.position.drag(DragStartDetails(), () {});
        drag.update(DragUpdateDetails(
            delta: const Offset(0, -80),
            primaryDelta: -80,
            globalPosition: const Offset(180, 410)));
        await tester.pump();
        expect(controller.position.isScrollingNotifier.value, isTrue);
        final during = (await tester.runAsync(pixels))!;
        drag.end(DragEndDetails(primaryVelocity: 0));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        final after = (await tester.runAsync(pixels))!;
        // Both surfaces must still match when the library cannot use its shader.
        LightweightLiquidGlass.resetForTesting();
        update(() => useMaterial3 = false);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        final withoutShader = (await tester.runAsync(pixels))!;
        expect(controller.offset, 80);
        for (var y = 45; y < 65; y += 3) {
          for (var x = 65; x < 325; x += 7) {
            final offset = (y * 390 + x) * 4;
            for (var channel = 0; channel < 3; channel++) {
              for (final frame in [during, after]) {
                expect(
                    (before[offset + channel] - frame[offset + channel]).abs(),
                    lessThanOrEqualTo(2),
                    reason:
                        'Card material changed at ($x, $y), channel $channel');
              }
            }
          }
        }
        // Sample the bar between tab icons, outside its selected indicator,
        // and the card at the same relative height over the same vertical stripes.
        final bar = tester.getRect(find.byType(GlassTabBar));
        const cardCentre = (50 * 390 + 158) * 4;
        final barCentre = ((bar.top + 30).round() * 390 + 158) * 4;
        for (final frame in [before, during, after, withoutShader]) {
          for (var channel = 0; channel < 3; channel++) {
            expect(
                (frame[cardCentre + channel] - frame[barCentre + channel])
                    .abs(),
                lessThanOrEqualTo(3),
                reason:
                    'Card and navigation bar use different glass material.');
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final brightness in Brightness.values) {
    testWidgets(
        'clear cards preserve wallpaper pixels at rest, during drag and after settling in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => LiquidGlassWidgets.initialize(
          enablePerformanceMonitor: false, warmUpMode: GlassWarmUpMode.never));
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
                        const Padding(
                            padding: EdgeInsets.only(bottom: 20),
                            child: MusicGlassPanel(
                                child: SizedBox(
                                    height: 120, width: double.infinity))),
                    ])),
              ])),
        ),
      ));
      await tester.pumpAndSettle();
      Future<Uint8List> pixels() async {
        final boundary = capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
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
          final rgba = [(argb >> 16) & 255, (argb >> 8) & 255, argb & 255, 255];
          for (var channel = 0; channel < 4; channel++) {
            expect(before![offset + channel], rgba[channel]);
            expect((before[offset + channel] - during![offset + channel]).abs(),
                lessThanOrEqualTo(2));
            expect((during[offset + channel] - after![offset + channel]).abs(),
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

class _Wallpaper extends CustomPainter {
  final bool verticalOnly;
  const _Wallpaper({this.verticalOnly = false});
  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0; y < size.height; y += 8) {
      for (var x = 0; x < size.width; x += 8) {
        canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), y.toDouble(), 8, 8),
            Paint()
              ..color = ((x ~/ 8) + (verticalOnly ? 0 : y ~/ 8)).isEven
                  ? Colors.lightBlue
                  : Colors.orange);
      }
    }
  }

  @override
  bool shouldRepaint(_Wallpaper oldDelegate) =>
      verticalOnly != oldDelegate.verticalOnly;
}
