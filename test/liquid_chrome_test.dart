import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musix/api/api_client.dart';
import 'package:musix/models/models.dart';
import 'package:musix/stores/player_store.dart';
import 'package:musix/stores/session_store.dart';
import 'package:musix/stores/ui_store.dart';
import 'package:musix/theme/glass.dart';
import 'package:musix/theme/theme.dart';
import 'package:musix/views/mini_player.dart';
import 'package:musix/views/shell.dart';
import 'package:provider/provider.dart';

const tabs = [
  AppTab.home,
  AppTab.library,
  AppTab.recents,
  AppTab.profile,
  AppTab.search
];

// No audio engine or server is needed to exercise the real controls.
class _Player extends ChangeNotifier implements PlayerStore {
  @override
  Track get track =>
      Track(id: 'test', platform: 'local', title: '测试歌曲', artists: ['测试歌手']);
  @override
  double get duration => 180;
  @override
  double get current => 30;
  @override
  bool get favorited => false;
  @override
  bool get loading => false;
  @override
  bool get playing => false;
  @override
  bool get shuffle => false;
  @override
  int get repeatMode => 0;
  int toggles = 0;
  @override
  Future<void> toggle() async => toggles++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session extends ChangeNotifier implements SessionStore {
  @override
  final api = APIClient(baseURL: 'http://localhost');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget harness(
  Widget child, {
  Brightness brightness = Brightness.light,
  GlassQuality quality = GlassQuality.minimal,
}) {
  MXBrightness.value = brightness;
  return LiquidGlassWidgets.wrap(
    brightnessResolver: Theme.maybeBrightnessOf,
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      themeAnimationDuration: Duration.zero,
      home: GlassAdaptiveScope(
        // Lock quality so timing-based adaptation cannot affect layout tests.
        minQuality: quality,
        maxQuality: quality,
        child: MediaQuery(
          data: const MediaQueryData(
              size: Size(390, 844), padding: EdgeInsets.only(bottom: 24)),
          child: AppBackdrop(
            enableLiquidGlass: true,
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('standard glass shaders load with the shared backdrop',
      (tester) async {
    await tester.runAsync(() => LiquidGlassWidgets.initialize(
          enablePerformanceMonitor: false,
          warmUpMode: GlassWarmUpMode.never,
        ));
    await tester.pumpWidget(harness(
      Align(
          alignment: Alignment.bottomCenter,
          child: LiquidDock(
            current: AppTab.home,
            order: tabs,
            onSelect: (_) {},
          )),
      quality: GlassQuality.standard,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(GlassTabBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('dock retains compact height, safe area and tab actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = AppTab.home;
    await tester.pumpWidget(harness(
      Align(
        alignment: Alignment.bottomCenter,
        child: StatefulBuilder(
            builder: (context, setState) => LiquidDock(
                  current: selected,
                  order: tabs,
                  onSelect: (tab) => setState(() => selected = tab),
                )),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(LiquidDock)).height, 84);
    final rect = tester.getRect(find.byType(GlassTabBar));
    await tester.tapAt(
        Offset(rect.left + 12 + (rect.width - 24) * 0.9, rect.center.dy));
    await tester.pumpAndSettle();
    expect(selected, AppTab.search);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dock updates colours when app brightness changes in place',
      (tester) async {
    for (final brightness in [
      Brightness.light,
      Brightness.dark,
      Brightness.light
    ]) {
      await tester.pumpWidget(harness(
        Align(
            alignment: Alignment.bottomCenter,
            child: LiquidDock(
              current: AppTab.home,
              order: tabs,
              onSelect: (_) {},
            )),
        brightness: brightness,
      ));
      await tester.pumpAndSettle();
      final bar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      final context = tester.element(find.byType(LiquidDock));
      expect(bar.unselectedLabelColor, Theme.of(context).colorScheme.onSurface);
      expect(DefaultTextStyle.of(context).style.decoration,
          isNot(TextDecoration.underline));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('glass mini player keeps transport, queue and collapse controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final player = _Player();
    final session = _Session();
    final ui = UIStore();
    addTearDown(player.dispose);
    addTearDown(session.dispose);
    addTearDown(ui.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerStore>.value(value: player),
        ChangeNotifierProvider<SessionStore>.value(value: session),
        ChangeNotifierProvider<UIStore>.value(value: ui),
      ],
      child: harness(
          const Align(alignment: Alignment.bottomCenter, child: MiniPlayer())),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsOneWidget);
    expect(tester.getSize(find.byType(MiniPlayer)).height, 88);
    await tester.tap(find.byTooltip('播放'));
    expect(player.toggles, 1);
    await tester.tap(find.byTooltip('播放队列'));
    expect(ui.queueOpen, isTrue);
    await tester.tap(find.text('测试歌曲'));
    await tester.pumpAndSettle();
    expect(ui.playerExpanded, isTrue);
    expect(tester.getSize(find.byType(MiniPlayer)).height,
        lessThanOrEqualTo(MiniPlayer.expandedExtent));
    await tester.tap(find.byTooltip('收起播放器'));
    await tester.pumpAndSettle();
    expect(ui.playerExpanded, isFalse);
    expect(tester.getSize(find.byType(MiniPlayer)).height, 88);
    expect(tester.takeException(), isNull);
  });
}
