import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musix/api/api_client.dart';
import 'package:musix/models/models.dart';
import 'package:musix/stores/audio_source_loader.dart';

void main() {
  test('successful cache load never starts a second source', () async {
    final result = await loadAudioWithFallback<int>(
      cached: () async => 7,
      direct: () async => throw StateError('unexpected direct load'),
      stop: () async => fail('unexpected stop'),
      isCurrent: () => true,
      onCacheFailure: (_) => fail('unexpected failure'),
    );
    expect(result, 7);
  });

  test('cache timeout stops old source then plays the same direct source',
      () async {
    final events = <String>[];
    final pending = Completer<int>();
    final result = await loadAudioWithFallback<int>(
      cached: () => pending.future,
      direct: () async {
        events.add('direct');
        return 5;
      },
      stop: () async {
        events.add('stop');
      },
      isCurrent: () => true,
      onCacheFailure: (_) => events.add('failure'),
      cacheTimeout: const Duration(milliseconds: 5),
    );
    expect(result, 5);
    expect(events, ['failure', 'stop', 'direct']);
    pending.complete(1);
  });

  test('a cancelled request never stops or replaces a newer song', () async {
    await expectLater(
        loadAudioWithFallback<int>(
          cached: () async => throw StateError('old load failed'),
          direct: () async => throw StateError('must not load'),
          stop: () async => fail('must not stop'),
          isCurrent: () => false,
          onCacheFailure: (_) => fail('must not retry'),
        ),
        throwsStateError);
  });

  test('direct errors reach existing retry and skip handling', () async {
    await expectLater(
        loadAudioWithFallback<int>(
          cached: () async => throw StateError('cache rejected'),
          direct: () async => throw const FormatException('bad audio'),
          stop: () async {},
          isCurrent: () => true,
          onCacheFailure: (_) {},
        ),
        throwsFormatException);
  });

  test(
      'API headers without a complete body time out instead of spinning forever',
      () async {
    final body = StreamController<List<int>>();
    final client = MockClient.streaming((request, _) async =>
        http.StreamedResponse(body.stream, 200, request: request));
    final api = APIClient(
        baseURL: 'http://localhost',
        client: client,
        requestTimeout: const Duration(milliseconds: 10));
    try {
      await expectLater(
          api.getJson('/api/playback/intents/test', (v) => v),
          throwsA(isA<ApiError>()
              .having((e) => e.message, 'timeout message', contains('超时'))));
    } finally {
      await body.close();
      client.close();
    }
  });
}
