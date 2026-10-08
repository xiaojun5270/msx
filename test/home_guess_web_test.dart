import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musix/api/api_client.dart';
import 'package:musix/local/local_store.dart';
import 'package:musix/models/models.dart';
import 'package:musix/stores/player_store.dart';
import 'package:musix/stores/session_store.dart';
import 'package:musix/stores/ui_store.dart';
import 'package:musix/views/home_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glass_controls_test.dart' show app;

const _webTracks = [
  {'id': 'web-qq', 'platform': 'qqmusic', 'title': '网页推荐一'},
  {'id': 'web-kugou', 'platform': 'kugou', 'title': '网页推荐二'},
];

class _HomeAPI extends APIClient {
  _HomeAPI() : super(baseURL: 'http://localhost');
  final paths = <String>[];
  List<Map<String, dynamic>> guessResponses = [
    {'tracks': _webTracks}
  ];
  bool failGuess = false;

  @override
  Future<String> getRawBody(String path) async {
    paths.add(path);
    Map<String, dynamic> data = {};
    if (path == '/api/home/guess') {
      if (failGuess) throw const ApiError('推荐暂不可用', status: 503);
      data = guessResponses.length > 1
          ? guessResponses.removeAt(0)
          : guessResponses.single;
    } else if (path == '/api/home/daily') {
      data = {
        'items': [
          {'id': 'daily', 'title': '每日推荐', 'platform': 'qqmusic'}
        ],
        'tracks': [
          {'id': 'daily-track', 'platform': 'qqmusic', 'title': '每日歌曲'}
        ],
      };
    } else if (path == '/api/home/taste') {
      data = {
        'tracks': [
          {'id': 'taste-track', 'platform': 'qqmusic', 'title': '为你推荐歌曲'}
        ],
      };
    }
    return jsonEncode({
      'result': {'status': 'ok', 'data': data},
    });
  }
}

class _HomeSession extends ChangeNotifier implements SessionStore {
  _HomeSession(this.local, this.api);
  @override
  final LocalStore local;
  @override
  final _HomeAPI api;
  @override
  Map<String, BindingSummary> bindings = {};
  final pages = <String>[];

  @override
  Future<T?> fetchPage<T>(String path,
      {required String cacheKey,
      required T Function(Map<String, dynamic>) factory}) async {
    pages.add(path);
    return factory(path == '/api/my/playlists'
        ? {
            'playlists': [
              {
                'id': 'favorites',
                'kind': 'favorites',
                'tracks': [
                  {'id': 'liked', 'platform': 'qqmusic', 'title': '已收藏歌曲'}
                ],
              }
            ],
          }
        : {});
  }

  @override
  T? peekPage<T>(String key, T Function(Map<String, dynamic>) factory) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HomePlayer extends ChangeNotifier implements PlayerStore {
  @override
  List<Track> queue = [];
  @override
  bool get playing => false;
  @override
  bool get loading => false;
  @override
  bool shuffle = false;
  @override
  void toggleShuffle() => shuffle = !shuffle;
  @override
  Future<void> replaceQueue(List<Track> tracks,
      {required int start, PlaySource? source}) async {
    queue = List.of(tracks);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(_HomeSession, _HomePlayer)> _openHome(WidgetTester tester,
    {_HomeAPI? api, bool cachedGuess = false}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final local = await LocalStore.open();
  if (cachedGuess) {
    local.saveHomeRaw(
        'guess',
        jsonEncode({
          'result': {
            'status': 'ok',
            'data': {'tracks': _webTracks},
          },
        }));
  }
  final session = _HomeSession(local, api ?? _HomeAPI());
  final player = _HomePlayer();
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
    child: app(const HomeView()),
  ));
  await tester.pumpAndSettle();
  return (session, player);
}

void main() {
  testWidgets('guess uses the web home endpoint and its returned song order',
      (tester) async {
    final api = _HomeAPI()
      ..guessResponses = [
        {
          'tracks': [
            ..._webTracks,
            {'id': '', 'platform': 'qqmusic', 'title': '缺少 ID'},
            {'id': 'blank', 'platform': 'qqmusic', 'title': ''},
          ],
          'items': [
            {
              'id': 'playlist',
              'tracks': [
                {'id': 'nested', 'platform': 'qqmusic', 'title': '歌单内歌曲'}
              ],
            }
          ],
        }
      ];
    final (session, player) = await _openHome(tester, api: api);
    expect(
        api.paths.where((path) => path.contains('guess')), ['/api/home/guess']);
    expect(
        session.pages.any((path) => path.contains('guess-you-like')), isFalse);
    await tester.tap(find.byTooltip('播放'));
    await tester.pump();
    expect(player.queue.map((track) => track.key),
        ['qqmusic::web-qq', 'kugou::web-kugou']);
    expect(find.text('来自音乐平台的个性化推荐 · 2 首歌曲'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty web recommendations replace cache without other songs',
      (tester) async {
    final api = _HomeAPI()
      ..guessResponses = [
        {'tracks': []}
      ];
    final (session, player) =
        await _openHome(tester, api: api, cachedGuess: true);
    expect(find.text('猜你喜欢'), findsWidgets);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('猜你喜欢'), findsNothing);
    expect(player.queue, isEmpty);
    expect(
        api.paths.where((path) => path.contains('guess')), ['/api/home/guess']);
    expect(session.pages.any((path) => path == '/api/me/libraries/playlists'),
        isFalse);
    expect(session.pages.any((path) => path == '/api/my/playlists/favorites'),
        isFalse);
    expect(
        session.pages.any((path) => path.contains('kind=playlist')), isFalse);
    final cached = APIClient.decodeCached(
        session.local.homeRaw('guess')!, HomeShelf.fromJson);
    expect(cached!.tracks, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('server refreshing retries the same home recommendation endpoint',
      (tester) async {
    final api = _HomeAPI()
      ..guessResponses = [
        {'tracks': [], 'refreshing': true, 'retryAfterMs': 300},
        {'tracks': _webTracks},
      ];
    await _openHome(tester, api: api);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(api.paths.where((path) => path.contains('guess')),
        ['/api/home/guess', '/api/home/guess']);
    expect(find.text('来自音乐平台的个性化推荐 · 2 首歌曲'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable recommendations can retry without a fallback list',
      (tester) async {
    final api = _HomeAPI()..failGuess = true;
    await _openHome(tester, api: api);
    expect(find.text('猜你喜欢'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    api.failGuess = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(api.paths.where((path) => path.contains('guess')),
        ['/api/home/guess', '/api/home/guess']);
    expect(find.text('来自音乐平台的个性化推荐 · 2 首歌曲'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
