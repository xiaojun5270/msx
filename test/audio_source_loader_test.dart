import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musix/api/api_client.dart';
import 'package:musix/models/models.dart';
import 'package:musix/stores/audio_source_loader.dart';

void main() {
  test('direct loading does not invoke cache or wait for old stop/disposal',
      () async {
    final blockedOldStop = Completer<void>();
    final result = await loadDirectAudio<int>(
      load: () async => 7,
      isCurrent: () => true,
      onTimeout: () => fail('unexpected timeout'),
    );
    expect(result, 7);
    expect(blockedOldStop.isCompleted, isFalse);
    blockedOldStop.complete();
  });

  test('timeout retires the blocked engine without awaiting stop', () async {
    final pending = Completer<int>();
    var retired = false;
    await expectLater(
        loadDirectAudio<int>(
          load: () => pending.future,
          isCurrent: () => true,
          onTimeout: () => retired = true,
          timeout: const Duration(milliseconds: 5),
        ),
        throwsA(isA<TimeoutException>()));
    expect(retired, isTrue);
    pending.complete(1);
  });

  test('superseded timeout cannot retire the newer engine', () async {
    final pending = Completer<int>();
    var current = true;
    final task = loadDirectAudio<int>(
      load: () => pending.future,
      isCurrent: () => current,
      onTimeout: () => fail('must not retire the next engine'),
      timeout: const Duration(milliseconds: 5),
    );
    current = false;
    await expectLater(task, throwsA(isA<TimeoutException>()));
    pending.complete(1);
  });

  test('late source-ready event cannot publish the previous song', () async {
    final pending = Completer<int>();
    var current = true;
    final task = loadDirectAudio<int>(
        load: () => pending.future,
        isCurrent: () => current,
        onTimeout: () => fail('unexpected timeout'));
    current = false;
    pending.complete(10);
    await expectLater(task, throwsStateError);
  });

  test('native source errors reach existing retry and skip handling', () async {
    await expectLater(
        loadDirectAudio<int>(
          load: () async => throw const FormatException('bad audio'),
          isCurrent: () => true,
          onTimeout: () => fail('not a timeout'),
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
