import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musix/api/api_client.dart';
import 'package:musix/local/local_store.dart';
import 'package:musix/models/models.dart';
import 'package:musix/stores/player_store.dart';
import 'package:musix/stores/session_store.dart';
import 'package:musix/stores/ui_store.dart';
import 'package:musix/views/mini_player.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glass_controls_test.dart' show app;

class _PlaybackAPI extends APIClient {
  _PlaybackAPI() : super(baseURL: 'http://localhost');
  final response = Completer<Map<String, dynamic>>();
  final List<Object?> playbackRequests = [];

  @override
  Future<T> postJson<T>(String path, T Function(Map<String, dynamic>) factory,
      {Object? json}) async {
    if (path == '/api/playback/sessions') {
      playbackRequests.add(json);
      return factory(await response.future);
    }
    return factory({});
  }

  @override
  Future<void> delete(String path) async {}
}

class _Session extends ChangeNotifier implements SessionStore {
  @override
  final LocalStore local;
  @override
  final _PlaybackAPI api = _PlaybackAPI();
  _Session(this.local);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final expanded in [false, true]) {
    testWidgets(
        'real player receives exactly one play request from ${expanded ? 'expanded' : 'collapsed'} glass button',
        (tester) async {
      // Native decode/output are intentionally outside this UI-to-API diagnosis.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in [
        'com.ryanheise.audio_session',
        'com.ryanheise.just_audio.methods',
        'home_widget'
      ]) {
        messenger.setMockMethodCallHandler(
            MethodChannel(name), (_) async => null);
        addTearDown(() =>
            messenger.setMockMethodCallHandler(MethodChannel(name), null));
      }
      SharedPreferences.setMockInitialValues({});
      final session = _Session(await LocalStore.open());
      final ui = UIStore()..playerExpanded = expanded;
      final player = PlayerStore();
      final originalEngine = player.engine;
      final track = Track(
          id: 'diagnostic', platform: 'kugou', title: '播放测试', artists: ['歌手']);
      player.queue = [track];
      player.index = 0;
      player.bind(session: session, ui: ui);
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerStore>.value(value: player),
            ChangeNotifierProvider<SessionStore>.value(value: session),
            ChangeNotifierProvider<UIStore>.value(value: ui),
          ],
          child: app(const Align(
              alignment: Alignment.bottomCenter, child: MiniPlayer()))));
      await tester.pump();
      await tester.tap(find.byTooltip('播放'));
      await tester.pump();
      expect(session.api.playbackRequests, hasLength(1));
      expect(player.engine, isNot(same(originalEngine)));
      final loadingEngine = player.engine;
      expect(player.loading, isTrue);
      expect(find.byTooltip('取消加载'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(session.api.playbackRequests, hasLength(1));
      expect(player.loading, isTrue);
      // The same button must cancel the pending load, not start a second one.
      await tester.tap(find.byTooltip('取消加载'));
      await tester.pump();
      expect(player.loading, isFalse);
      expect(player.engine, isNot(same(loadingEngine)));
      session.api.response
          .complete({'status': 'failed', 'reason': 'diagnostic cancelled'});
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
      ui.dispose();
      session.dispose();
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Mock platform disposal can remain pending; it must not block the UI.
      await tester.pump(const Duration(seconds: 4));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
