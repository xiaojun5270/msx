import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musix/api/api_client.dart';
import 'package:musix/models/models.dart';
import 'package:musix/stores/guess_feed.dart';
import 'package:musix/stores/session_store.dart';

class _GuessAPI extends APIClient {
  _GuessAPI(this.pages, {this.historyPages}) : super(baseURL: 'http://localhost');

  final List<Map<String, dynamic>> pages;
  final List<List<Map<String, dynamic>>>? historyPages;
  final paths = <String>[];

  @override
  Future<T> getJson<T>(
      String path, T Function(Map<String, dynamic>) factory) async {
    if (path.startsWith('/api/me/history')) {
      final history = historyPages;
      if (history == null || history.isEmpty) {
        throw const ApiError('history unavailable');
      }
      return factory({'items': history.removeAt(0)}) as T;
    }
    paths.add(path);
    final page = pages.removeAt(0);
    return factory(page) as T;
  }
}

class _GuessSession extends ChangeNotifier implements SessionStore {
  _GuessSession(this.api);

  @override
  final APIClient api;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('uses the iOS recommendation endpoint and paginates with exclusions',
      () async {
    final api = _GuessAPI([
      {
        'tracks': [
          {'id': 'a', 'platform': 'qqmusic', 'title': 'A'},
          {'id': 'a', 'platform': 'qqmusic', 'title': 'A duplicate'},
          {'id': '', 'platform': 'qqmusic', 'title': 'Missing ID'},
        ],
        'sources': [
          {'platform': 'qqmusic', 'label': 'QQ 音乐', 'trackCount': 1},
        ],
        'hasMore': true,
        'nextOffset': 24,
        'total': 2,
      },
      {
        'tracks': [
          {'id': 'a', 'platform': 'qqmusic', 'title': 'A again'},
          {'id': 'b', 'platform': 'kugou', 'title': 'B'},
        ],
        'hasMore': false,
        'nextOffset': 48,
      },
    ]);
    final feed = GuessFeed(_GuessSession(api));

    expect(await feed.loadFirst(), isTrue);
    expect(feed.tracks.map((track) => track.key), ['qqmusic::a']);
    expect(feed.sources.single.platform, 'qqmusic');
    expect(feed.total, 2);
    expect(feed.hasMore, isTrue);

    expect(await feed.loadMore(), isTrue);
    expect(feed.tracks.map((track) => track.key), ['qqmusic::a', 'kugou::b']);
    expect(api.paths, [
      '/api/guess-you-like?limit=24&offset=0',
      '/api/guess-you-like?limit=24&offset=24&exclude=qqmusic%3A%3Aa',
    ]);
  });

  test('loadAll chains pages and keeps only already-played tracks', () async {
    final api = _GuessAPI([
      {
        'tracks': [
          {'id': 'a', 'platform': 'qqmusic', 'title': 'A'},
          {'id': 'c', 'platform': 'qqmusic', 'title': 'C unplayed'},
        ],
        'sources': [
          {'platform': 'qqmusic', 'label': 'QQ 音乐', 'trackCount': 2},
        ],
        'hasMore': true,
        'nextOffset': 24,
      },
      {
        'tracks': [
          {'id': 'b', 'platform': 'kugou', 'title': 'B'},
          {'id': 'd', 'platform': 'kugou', 'title': 'D unplayed'},
        ],
        'hasMore': false,
        'nextOffset': 48,
      },
    ], historyPages: [
      [
        {'id': 'a', 'platform': 'qqmusic', 'title': 'A'},
        {'id': 'b', 'platform': 'kugou', 'title': 'B'},
      ],
    ]);
    final feed = GuessFeed(_GuessSession(api));

    expect(await feed.loadFirst(loadAll: true), isTrue);
    expect(feed.tracks.map((track) => track.key), ['qqmusic::a', 'kugou::b']);
    expect(feed.hasMore, isFalse);
    expect(api.paths, [
      '/api/guess-you-like?limit=24&offset=0',
      '/api/guess-you-like?limit=24&offset=24&exclude=qqmusic%3A%3Aa',
    ]);
  });

  test('a failed history fetch disables the played filter instead of '
      'emptying the feed', () async {
    final api = _GuessAPI([
      {
        'tracks': [
          {'id': 'a', 'platform': 'qqmusic', 'title': 'A'},
        ],
        'hasMore': false,
      },
    ]);
    final feed = GuessFeed(_GuessSession(api));

    expect(await feed.loadFirst(), isTrue);
    expect(feed.tracks.map((track) => track.key), ['qqmusic::a']);
  });

  test('fetchRandom keeps only played tracks and honours avoidKeys', () async {
    final api = _GuessAPI([
      {
        'tracks': [
          {'id': 'a', 'platform': 'qqmusic', 'title': 'A'},
          {'id': 'c', 'platform': 'qqmusic', 'title': 'C unplayed'},
        ],
        'hasMore': false,
      },
    ], historyPages: [
      [
        {'id': 'a', 'platform': 'qqmusic', 'title': 'A'},
      ],
    ]);
    final feed = GuessFeed(_GuessSession(api));

    final picked = await feed.fetchRandom();
    expect(picked?.key, 'qqmusic::a');

    final avoided = await feed.fetchRandom(avoidKeys: {'qqmusic::a'});
    expect(avoided, isNull);
  });

  test('refresh keeps the selected platform and excludes visible songs',
      () async {
    final api = _GuessAPI([
      {
        'tracks': [
          {'id': 'a', 'platform': 'qqmusic', 'title': 'A'},
          {'id': 'k1', 'platform': 'kugou', 'title': 'K1'},
        ],
        'hasMore': false,
      },
      {
        'tracks': [
          {'id': 'k2', 'platform': 'kugou', 'title': 'K2'},
        ],
        'hasMore': false,
      },
    ]);
    final feed = GuessFeed(_GuessSession(api));

    await feed.loadFirst();
    expect(await feed.refresh(platform: 'kugou'), isTrue);
    expect(feed.tracks.map((track) => track.key), ['qqmusic::a', 'kugou::k2']);
    expect(api.paths.last,
        '/api/guess-you-like?limit=24&offset=0&platform=kugou&exclude=kugou%3A%3Ak1%2Cqqmusic%3A%3Aa');
  });
}
