import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musix/local/local_store.dart';
import 'package:musix/stores/session_store.dart';
import 'package:musix/stores/ui_store.dart';
import 'package:musix/theme/player_glass.dart';
import 'package:musix/theme/theme.dart';
import 'package:musix/views/settings_views.dart';

import 'glass_controls_test.dart' show app;
import 'refresh_and_glass_state_test.dart' show HomeSession;

void main() {
  testWidgets('glass material defaults to liquid and persists the choice',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final local = await LocalStore.open();
    final ui = UIStore()..loadAppearance(local);
    addTearDown(ui.dispose);

    expect(ui.glassMaterial, GlassMaterial.liquid);

    ui.setGlassMaterial(GlassMaterial.frosted, local);
    expect(ui.glassMaterial, GlassMaterial.frosted);
    expect(local.prefs.glassMaterial, 'frosted');

    // A fresh store reads the persisted material back.
    final reopened = await LocalStore.open();
    expect(reopened.glassMaterial, GlassMaterial.frosted);
  });

  testWidgets('playerGlassSettings switches between the two materials',
      (tester) async {
    late BuildContext captured;
    final ui = UIStore();
    addTearDown(ui.dispose);
    await tester.pumpWidget(app(
      ChangeNotifierProvider<UIStore>.value(
        value: ui,
        child: Builder(builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        }),
      ),
    ));

    expect(playerGlassSettings(captured).refractiveIndex, 1.18);
    expect(playerGlassSettings(captured).thickness, 24);

    ui.glassMaterial = GlassMaterial.frosted;
    await tester.pump();
    final frosted = playerGlassSettings(captured);
    expect(frosted.refractiveIndex, 1.0);
    expect(frosted.thickness, 0);
    expect(frosted.chromaticAberration, 0);
    expect(frosted.blur, greaterThan(10));
  });

  testWidgets('settings exposes the 界面材质 picker and applies the choice',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final local = await LocalStore.open();
    final session = HomeSession(local);
    final ui = UIStore()..loadAppearance(local);
    addTearDown(session.dispose);
    addTearDown(ui.dispose);

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<SessionStore>.value(value: session),
      ChangeNotifierProvider<UIStore>.value(value: ui),
    ], child: app(const SettingsView())));
    await tester.pump();

    expect(find.text('界面材质'), findsOneWidget);
    expect(find.text('液态玻璃'), findsOneWidget);

    await tester.tap(find.text('界面材质'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // The menu shows both materials with the current one checked.
    expect(find.text('毛玻璃'), findsWidgets);
    await tester.tap(find.text('毛玻璃').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(ui.glassMaterial, GlassMaterial.frosted);
    expect(local.prefs.glassMaterial, 'frosted');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
