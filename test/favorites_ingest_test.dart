import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musix/api/api_client.dart';
import 'package:musix/models/models.dart';
import 'package:musix/stores/player_store.dart';
import 'package:musix/stores/session_store.dart';
import 'package:musix/stores/ui_store.dart';
import 'package:musix/views/explore_views.dart';
import 'package:provider/provider.dart';

import 'glass_controls_test.dart' show app;

class _IngestAPI extends APIClient {
  _IngestAPI() : super(baseURL: 'http://localhost');
  final tracks = <Map<String, dynamic>>[
    {
      'id': 'q',
      'platform': 'qqmusic',
      'title': 'QQ歌曲',
      'artists': ['歌手'],
      'artistIds': ['artist-q'],
      'streamUrl': 'https://example.com/preview.mp3',
    },
    {'id': 'k', 'platform': 'kugou', 'title': '酷狗歌曲', 'artists': []},
    {'id': 'local', 'platform': 'local', 'title': '本地歌曲'},
    {
      'id': 'imported',
      'platform': 'qqmusic',
      'title': '已入库歌曲',
      'streamUrl': '/api/library/tracks/imported',
    },
  ];
  final writes = <Object?>[];
  Completer<Map<String, dynamic>>? pending;
  bool fail = false;

  @override
  Future<T> getJson<T>(
      String path, T Function(Map<String, dynamic>) factory) async {
    if (path == '/api/my/playlists') {
      return factory({
        'playlists': [
          {'id': 'favorites', 'kind': 'favorites'}
        ],
      });
    }
    if (path == '/api/my/playlists/favorites') {
      return factory({
        'playlist': {'id': 'favorites', 'tracks': tracks},
      });
    }
    return factory({});
  }

  @override
  Future<T> postJson<T>(String path, T Function(Map<String, dynamic>) factory,
      {Object? json}) async {
    expect(path, '/api/library/ingest/batch');
    writes.add(json);
    if (fail) throw const ApiError('服务器暂不可用', status: 503);
    return factory(await pending?.future ?? {'queued': 2});
  }
}

class _FavoritesSession extends ChangeNotifier implements SessionStore {
  @override
  final _IngestAPI api = _IngestAPI();
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

class _IdlePlayer extends ChangeNotifier implements PlayerStore {
  @override
  Track? get track => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(_IngestAPI, UIStore)> _openFavorites(WidgetTester tester,
    {bool localOnly = false}) async {
  final session = _FavoritesSession();
  if (localOnly) session.api.tracks.removeRange(0, 2);
  final player = _IdlePlayer();
  final ui = UIStore();
  addTearDown(session.dispose);
  addTearDown(player.dispose);
  addTearDown(ui.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionStore>.value(value: session),
      ChangeNotifierProvider<PlayerStore>.value(value: player),
      ChangeNotifierProvider<UIStore>.value(value: ui),
    ],
    child: app(const FavoritesView()),
  ));
  await tester.pumpAndSettle();
  return (session.api, ui);
}

Future<void> _confirmDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('一键入库'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('favorites confirmation submits only remote song identities',
      (tester) async {
    final (api, ui) = await _openFavorites(tester);
    api.pending = Completer<Map<String, dynamic>>();
    await _confirmDialog(tester);
    expect(find.text('将 2 首歌曲入库到本地？'), findsOneWidget);
    expect(api.writes, isEmpty);
    await tester.tap(find.text('入库'));
    await tester.pumpAndSettle();
    expect(api.writes, [
      {
        'items': [
          {
            'id': 'q',
            'platform': 'qqmusic',
            'title': 'QQ歌曲',
            'artists': ['歌手'],
            'artistIds': ['artist-q'],
          },
          {'id': 'k', 'platform': 'kugou', 'title': '酷狗歌曲', 'artists': []},
        ],
      }
    ]);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    final item = find.byWidgetPredicate((widget) =>
        widget is PopupMenuItem<String> && widget.value == 'ingest');
    expect(tester.widget<PopupMenuItem<String>>(item).enabled, isFalse);
    await tester.tap(find.text('入库中…'));
    await tester.pump();
    expect(api.writes, hasLength(1));
    await tester.tapAt(const Offset(20, 500));
    await tester.pumpAndSettle();
    api.pending!.complete({'queued': 1, 'skipped': 1});
    await tester.pumpAndSettle();
    expect(ui.toast, '已加入 1 首，跳过 1 首');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling favorites ingestion sends no request',
      (tester) async {
    final (api, _) = await _openFavorites(tester);
    await _confirmDialog(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed ingestion reports error and can be retried',
      (tester) async {
    final (api, ui) = await _openFavorites(tester);
    api.fail = true;
    await _confirmDialog(tester);
    await tester.tap(find.text('入库'));
    await tester.pumpAndSettle();
    expect(ui.toast, contains('入库失败'));
    api.fail = false;
    await _confirmDialog(tester);
    await tester.tap(find.text('入库'));
    await tester.pumpAndSettle();
    expect(api.writes, hasLength(2));
    expect(ui.toast, '已加入 2 首');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('local favorites retain playback and organize without ingestion',
      (tester) async {
    final (api, _) = await _openFavorites(tester, localOnly: true);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('一键入库'), findsNothing);
    expect(find.text('整理音源'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);
    expect(api.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
