import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musix/theme/route.dart';
import 'package:musix/stores/ui_store.dart';
import 'package:provider/provider.dart';

void main() {
  test('ordinary page routes are immediate and opaque', () {
    final route = instantPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );

    expect(route.opaque, isTrue);
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });

  testWidgets('a pushed page fully replaces the previous page', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => UIStore(),
        child: WidgetsApp(
          color: const Color(0x00000000),
          builder: (context, child) => child!,
          onGenerateRoute: (_) => instantPageRoute<void>(
            builder: (context) => Directionality(
              textDirection: TextDirection.ltr,
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  instantPageRoute<void>(
                    builder: (_) => const Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text('next page'),
                    ),
                  ),
                ),
                child: const Text('previous page'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('previous page'));
    await tester.pump();

    expect(find.text('next page'), findsOneWidget);
    expect(find.text('previous page'), findsNothing);
  });

  testWidgets('transparent Material clears the WidgetsApp error decoration',
      (tester) async {
    TextStyle? inheritedStyle;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          type: MaterialType.transparency,
          child: Builder(
            builder: (context) {
              inheritedStyle = DefaultTextStyle.of(context).style;
              return const Text('overlay label');
            },
          ),
        ),
      ),
    );

    expect(inheritedStyle?.decoration, isNot(TextDecoration.underline));
    expect(inheritedStyle?.decorationStyle, isNot(TextDecorationStyle.double));
    expect(inheritedStyle?.decorationColor, isNot(const Color(0xFFFFFF00)));
  });

  testWidgets('keyboard inset keeps input visible and hides bottom chrome',
      (tester) async {
    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final keyboardVisible =
                MediaQuery.viewInsetsOf(context).bottom > 0;
            return Stack(
              children: [
                Scaffold(
                  resizeToAvoidBottomInset: false,
                  body: Scaffold(
                    body: TextField(
                      key: const Key('keyboard-input'),
                      decoration: const InputDecoration(hintText: 'Input'),
                    ),
                  ),
                ),
                if (!keyboardVisible)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Text('bottom overlay'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('keyboard-input')));
    await tester.showKeyboard(find.byKey(const Key('keyboard-input')));
    await tester.pump();

    expect(find.byKey(const Key('keyboard-input')), findsOneWidget);
    expect(find.text('bottom overlay'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
