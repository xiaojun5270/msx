import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musix/api/api_client.dart';
import 'package:musix/models/models.dart';
import 'package:musix/stores/session_store.dart';
import 'package:musix/stores/ui_store.dart';
import 'package:musix/views/account_view.dart';
import 'package:provider/provider.dart';

import 'glass_controls_test.dart' show app;

class _PlaylistAPI extends APIClient {
  _PlaylistAPI() : super(baseURL: 'http://localhost');
  final playlists = <Map<String, dynamic>>[
    {'id': 'favorites', 'name': '收藏', 'kind': 'favorites'},
  ];
  final writes = <Object?>[];
  Completer<void>? pending;
  bool fail = false;

  @override
  Future<T> getJson<T>(
          String path, T Function(Map<String, dynamic>) factory) async =>
      factory(path == '/api/my/playlists' ? {'playlists': playlists} : {});

  @override
  Future<void> post(String path, {Object? json}) async {
    expect(path, '/api/my/playlists');
    writes.add(json);
    await pending?.future;
    if (fail) throw const ApiError('服务器暂不可用', status: 503);
    playlists.add({
      'id': 'new-${writes.length}',
      'name': (json as Map<String, dynamic>)['name'],
      'platform': 'local',
      'listKind': 'mine',
    });
  }
}

class _AccountSession extends ChangeNotifier implements SessionStore {
  @override
  final _PlaylistAPI api = _PlaylistAPI();
  @override
  Map<String, BindingSummary> bindings = {};
  @override
  String get nickname => '测试账户';
  @override
  String get role => 'user';
  @override
  String? get avatarUrl => null;
  @override
  Future<void> refreshBindings() async {}
  @override
  Future<void> apply(Me me) async {}
  @override
  T? peekPage<T>(String key, T Function(Map<String, dynamic>) factory) => null;
  @override
  Future<T?> fetchPage<T>(String path,
          {required String cacheKey,
          required T Function(Map<String, dynamic>) factory}) =>
      api.getJson(path, factory);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(_AccountSession, UIStore)> _openAccount(WidgetTester tester,
    {Brightness brightness = Brightness.light, bool existing = false}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = _AccountSession();
  if (existing) {
    session.api.playlists.add({'id': 'existing', 'name': '已有歌单'});
  }
  final ui = UIStore();
  addTearDown(session.dispose);
  addTearDown(ui.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionStore>.value(value: session),
      ChangeNotifierProvider<UIStore>.value(value: ui),
    ],
    child: app(const AccountView(), brightness: brightness),
  ));
  await tester.pumpAndSettle();
  return (session, ui);
}

Finder get _createButton => find.byWidgetPredicate(
    (widget) => widget is GlassButton && widget.label == '新建歌单');

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('profile creates and refreshes playlists in $brightness',
        (tester) async {
      final existing = brightness == Brightness.light;
      final (session, ui) = await _openAccount(tester,
          brightness: brightness, existing: existing);
      session.api.pending = Completer<void>();
      expect(find.text('还没有歌单'), existing ? findsNothing : findsOneWidget);
      await tester.tap(_createButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  夜间音乐  ');
      await tester.tap(find.text('创建'));
      await tester.pump();
      expect(session.api.writes, [
        {'name': '夜间音乐'}
      ]);
      expect(find.text('创建中'), findsOneWidget);
      expect(tester.widget<GlassButton>(_createButton).enabled, isFalse);
      await tester.tap(_createButton);
      await tester.pump();
      expect(session.api.writes, hasLength(1));
      session.api.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('夜间音乐'), findsOneWidget);
      expect(find.text(existing ? '2 个' : '1 个'), findsOneWidget);
      expect(find.text('收藏'), findsNothing);
      expect(ui.toast, '已创建');
      expect(tester.widget<GlassButton>(_createButton).enabled, isTrue);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('blank names and cancel never create a playlist', (tester) async {
    final (session, _) = await _openAccount(tester);
    await tester.tap(_createButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('请输入歌单名称'), findsOneWidget);
    expect(session.api.writes, isEmpty);
    await tester.enterText(find.byType(TextField), '取消的歌单');
    await tester.pump();
    expect(find.text('请输入歌单名称'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(session.api.writes, isEmpty);
    expect(find.text('还没有歌单'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed creation allows retry and keyboard submission',
      (tester) async {
    final (session, ui) = await _openAccount(tester);
    session.api.fail = true;
    await tester.tap(_createButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '重试歌单');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(ui.toast, contains('创建失败'));
    expect(find.text('重试歌单'), findsNothing);
    expect(tester.widget<GlassButton>(_createButton).enabled, isTrue);
    session.api.fail = false;
    await tester.tap(_createButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '重试歌单');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(session.api.writes, hasLength(2));
    expect(find.text('重试歌单'), findsOneWidget);
    expect(ui.toast, '已创建');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
