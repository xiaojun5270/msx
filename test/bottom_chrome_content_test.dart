import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musix/theme/bottom_chrome.dart';
import 'package:musix/theme/player_glass.dart';

void main() {
  for (final layout in ['list', 'grid', 'slivers']) {
    testWidgets(
        '$layout paints behind controls and scrolls last item above them',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var extent = 260.0;
      late StateSetter update;

      Widget row(int i) => SizedBox(
            key: ValueKey('row-$i'),
            height: 60,
            child: ColoredBox(
                color: i.isEven ? Colors.blue : Colors.amber,
                child: Text('Row $i')),
          );

      await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return LiquidGlassScope(
              child: Stack(children: [
            GlassBackgroundSource(
                child: BottomChromeContent(
              extent: extent,
              child: Scaffold(body: Builder(builder: (context) {
                final bottom = MediaQuery.paddingOf(context).bottom;
                final padding = EdgeInsets.only(bottom: bottom);
                if (layout == 'grid') {
                  return GridView.builder(
                      controller: controller,
                      padding: padding,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, mainAxisExtent: 60),
                      itemCount: 60,
                      itemBuilder: (_, i) => row(i));
                }
                if (layout == 'slivers') {
                  return CustomScrollView(controller: controller, slivers: [
                    SliverPadding(
                        padding: padding,
                        sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                                (_, i) => row(i),
                                childCount: 60))),
                  ]);
                }
                return ListView.builder(
                    controller: controller,
                    padding: padding,
                    itemCount: 60,
                    itemBuilder: (_, i) => row(i));
              })),
            )),
            Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                    child:
                        SizedBox(key: const Key('controls'), height: extent))),
          ]));
        },
      )));
      await tester.pump();
      // The old outer Padding shrank this viewport by 260 pixels.
      expect(controller.position.viewportDimension, 844);
      final underGlass =
          find.byKey(ValueKey(layout == 'grid' ? 'row-24' : 'row-12'));
      expect(tester.getRect(underGlass).top,
          greaterThan(tester.getRect(find.byKey(const Key('controls'))).top));
      expect(tester.getRect(underGlass).bottom, lessThan(844));
      expect(
          find.ancestor(
              of: underGlass, matching: find.byType(GlassBackgroundSource)),
          findsOneWidget);
      // Both expanded and collapsed control heights update the scrollable tail.
      for (final nextExtent in [260.0, 174.0, 84.0]) {
        update(() => extent = nextExtent);
        await tester.pump();
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pump();
        final last = tester.getRect(find.byKey(const ValueKey('row-59')));
        expect(last.bottom, closeTo(844 - extent, 0.1));
        expect(controller.position.viewportDimension, 844);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
      'keyboard removes chrome inset and root overlays do not inherit it',
      (tester) async {
    double? pageInset;
    double? dialogInset;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
      child: BottomChromeContent(
        extent: 260,
        child: Builder(builder: (context) {
          pageInset = MediaQuery.paddingOf(context).bottom;
          return TextButton(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) {
                    dialogInset = MediaQuery.paddingOf(context).bottom;
                    return const AlertDialog(content: Text('dialog'));
                  }),
              child: const Text('open'));
        }),
      ),
    )));
    expect(pageInset, 0);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(dialogInset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass has no fixed light or dark body tint', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Builder(builder: (context) {
          final settings = playerGlassSettings(context);
          expect(settings.glassColor, Colors.transparent);
          expect(settings.blur, greaterThan(0));
          expect(settings.thickness, greaterThan(0));
          return const SizedBox.shrink();
        }),
      ));
    }
  });
}
