import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musix/api/api_client.dart';
import 'package:musix/local/local_store.dart';
import 'package:musix/models/models.dart';
import 'package:musix/stores/session_store.dart';
import 'package:musix/stores/player_store.dart';
import 'package:musix/stores/ui_store.dart';
import 'package:musix/theme/glass.dart';
import 'package:musix/views/home_view.dart';
import 'package:musix/views/settings_views.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glass_controls_test.dart' show app, QueuePlayer;

class StalledAPI extends APIClient {
  final pending = Completer<String>();
  StalledAPI() : super(baseURL: 'http://localhost');
  @override
  Future<String> getRawBody(String path) => pending.future;
  @override
  Future<T> getJson<T>(
          String path, T Function(Map<String, dynamic>) factory) async =>
      factory({});
}

class HomeSession extends ChangeNotifier implements SessionStore {
  @override
  final LocalStore local;
  @override
  final StalledAPI api;
  @override
  Map<String, BindingSummary> bindings = {};
  HomeSession(this.local, {StalledAPI? api}) : api = api ?? StalledAPI();
  @override
  String get nickname => '测试账户';
  @override
  String? get avatarUrl => null;
  @override
  String get baseURL => 'http://localhost';
  @override
  Future<T?> fetchPage<T>(String path,
          {required String cacheKey,
          required T Function(Map<String, dynamic>) factory}) async =>
      factory({});
  @override
  T? peekPage<T>(String key, T Function(Map<String, dynamic>) factory) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DelayedSettingsAPI extends StalledAPI {
  final bindingResponse = Completer<Map<String, dynamic>>();
  final versionResponse = Completer<Map<String, dynamic>>();
  @override
  Future<T> getJson<T>(
      String path, T Function(Map<String, dynamic>) factory) async {
    if (path == '/api/me/bindings')
      return factory(await bindingResponse.future);
    if (path == '/api/version') return factory(await versionResponse.future);
    return factory({});
  }
}

void main() {
  testWidgets(
      'settings renders real bindings before unrelated slow requests complete',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final local = await LocalStore.open();
    final api = DelayedSettingsAPI();
    final session = HomeSession(local, api: api);
    final ui = UIStore();
    addTearDown(session.dispose);
    addTearDown(ui.dispose);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<SessionStore>.value(value: session),
      ChangeNotifierProvider<UIStore>.value(value: ui),
    ], child: app(const SettingsView())));
    await tester.pump();
    expect(find.text('未连接'), findsNothing);
    expect(find.text('读取中'), findsWidgets);
    api.bindingResponse.complete({
      'bindings': {
        'kugou': {'bound': true, 'nickname': '已登录的酷狗账户'}
      }
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('已登录的酷狗账户'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
    expect(api.versionResponse.isCompleted, isFalse);
    api.versionResponse.complete({'version': 'test'});
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('stalled home request ends refresh and makes retry available',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final local = await LocalStore.open();
    final session = HomeSession(local);
    final ui = UIStore();
    final player = QueuePlayer();
    addTearDown(session.dispose);
    addTearDown(ui.dispose);
    addTearDown(player.dispose);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<SessionStore>.value(value: session),
      ChangeNotifierProvider<UIStore>.value(value: ui),
      ChangeNotifierProvider<PlayerStore>.value(value: player),
    ], child: app(const HomeView())));
    await tester.pump();
    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    var finished = false;
    unawaited(refresh.onRefresh().then((_) => finished = true));
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    expect(finished, isTrue);
    expect(find.text('重试'), findsOneWidget);
    // Late results must not restore the old loading state after the deadline.
    session.api.pending.complete('{}');
    await tester.pump();
    expect(find.text('重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'page controls sample a separate wallpaper while dock samples the page',
      (tester) async {
    GlobalKey? outer;
    GlobalKey? inner;
    await tester
        .pumpWidget(app(LiquidGlassScope(child: Builder(builder: (context) {
      outer = LiquidGlassScope.of(context);
      return GlassBackgroundSource(
          child: AppBackdrop(child: Builder(builder: (context) {
        inner = LiquidGlassScope.of(context);
        return const Text('当前设置状态');
      })));
    }))));
    expect(outer, isNotNull);
    expect(inner, isNotNull);
    expect(inner, isNot(same(outer)));
    expect(find.ancestor(of: find.text('当前设置状态'), matching: find.byKey(inner!)),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
