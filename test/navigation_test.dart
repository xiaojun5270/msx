import 'package:flutter/widgets.dart';
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
}
