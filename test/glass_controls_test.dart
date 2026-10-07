import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musix/api/api_client.dart';
import 'package:musix/models/models.dart';
import 'package:musix/stores/player_store.dart';
import 'package:musix/stores/session_store.dart';
import 'package:musix/stores/ui_store.dart';
import 'package:musix/theme/theme.dart';
import 'package:musix/views/components.dart';
import 'package:musix/views/glass_controls.dart';
import 'package:musix/views/sheets.dart';
import 'package:provider/provider.dart';

class QueuePlayer extends ChangeNotifier implements PlayerStore {
  @override
  List<Track> queue = List.generate(
      40,
      (i) =>
          Track(id: '$i', platform: 'test', title: '歌曲 $i', artists: ['歌手']));
  @override
  int index = 0;
  int cleared = 0;
  final List<Track> enqueued = [];
  @override
  Future<void> removeAt(int i) async {
    queue.removeAt(i);
    notifyListeners();
  }

  @override
  Future<void> clearQueue() async {
    cleared++;
    queue.clear();
    notifyListeners();
  }

  @override
  void enqueue(Track track) {
    enqueued.add(track);
  }

  @override
  Future<void> jumpTo(int i) async {
    index = i;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EmptyAPI extends APIClient {
  EmptyAPI() : super(baseURL: 'http://localhost');
  @override
  Future<T> getJson<T>(
          String path, T Function(Map<String, dynamic>) factory) async =>
      factory({});
  @override
  Future<T> postJson<T>(String path, T Function(Map<String, dynamic>) factory,
          {Object? json}) async =>
      factory({});
}

class SheetSession extends ChangeNotifier implements SessionStore {
  @override
  final api = EmptyAPI();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget app(Widget child, {Brightness brightness = Brightness.light}) {
  MXBrightness.value = brightness;
  return LiquidGlassWidgets.wrap(
    brightnessResolver: Theme.maybeBrightnessOf,
    adaptiveQuality: true,
    adaptiveConfig: const GlassAdaptiveScopeConfig(
        minQuality: GlassQuality.minimal, maxQuality: GlassQuality.minimal),
    child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        themeAnimationDuration: Duration.zero,
        builder: (_, child) =>
            Material(type: MaterialType.transparency, child: child!),
        home: Scaffold(body: child)),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('source and playlist sheets close cleanly in $brightness',
        (tester) async {
      final ui = UIStore();
      final session = SheetSession();
      final player = QueuePlayer();
      addTearDown(ui.dispose);
      addTearDown(session.dispose);
      addTearDown(player.dispose);
      ui.sourceTrack = player.queue.first;
      ui.pickerTrack = player.queue.first;
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UIStore>.value(value: ui),
            ChangeNotifierProvider<SessionStore>.value(value: session),
            ChangeNotifierProvider<PlayerStore>.value(value: player),
          ],
          child: app(
              Builder(
                  builder: (context) => Column(children: [
                        TextButton(
                            onPressed: () =>
                                showAuxSheet(context, const SourceSheet()),
                            child: const Text('打开换源')),
                        TextButton(
                            onPressed: () => showAuxSheet(
                                context, const PlaylistPickerSheet()),
                            child: const Text('打开歌单')),
                      ])),
              brightness: brightness)));
      await tester.tap(find.text('打开换源'));
      await tester.pumpAndSettle();
      expect(find.text('暂无其他音源'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开歌单'));
      await tester.pumpAndSettle();
      expect(find.text('暂无可用歌单'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassModalSheetScaffold), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('menu can open a sheet and retains destructive song actions',
      (tester) async {
    final player = QueuePlayer();
    final ui = UIStore();
    addTearDown(player.dispose);
    addTearDown(ui.dispose);
    var deleted = 0;
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerStore>.value(value: player),
          ChangeNotifierProvider<UIStore>.value(value: ui),
        ],
        child: app(Builder(
            builder: (context) => Column(children: [
                  TrackActionsMenu(
                      track: player.queue.first, onDelete: () => deleted++),
                  MusicActionsMenu(actions: [
                    MusicMenuAction('显示队列', Icons.queue_music,
                        () => showAuxSheet(context, const QueueSheet()))
                  ]),
                ])))));
    await tester.tap(find.byTooltip('歌曲操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除记录'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
    await tester.tap(find.byTooltip('歌曲操作').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示队列'));
    await tester.pumpAndSettle();
    expect(find.byType(QueueSheet), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('显示队列'), findsNothing);
    expect(find.byType(MusicActionsMenu), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('segmented categories keep a valid selection on repeated taps',
      (tester) async {
    var selected = 'track';
    await tester.pumpWidget(app(StatefulBuilder(
        builder: (_, update) => SegmentBar(
              items: const [
                ('track', '歌曲'),
                ('album', '专辑'),
                ('artist', '艺人'),
                ('playlist', '歌单')
              ],
              selected: selected,
              onChanged: (v) => update(() => selected = v),
            ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('专辑').first);
    await tester.pumpAndSettle();
    expect(selected, 'album');
    await tester.tap(find.text('专辑').first);
    await tester.pumpAndSettle();
    expect(selected, 'album');
    expect(find.byType(GlassSegmentedControl), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and long category lists work at narrow widths',
      (tester) async {
    await tester.pumpWidget(
        app(ChipBar(items: const [], selected: '', onChanged: (_) {})));
    expect(find.byType(GlassSegmentedControl), findsNothing);
    var selected = '0';
    await tester.pumpWidget(app(Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 240,
          child: StatefulBuilder(
              builder: (_, update) => ChipBar(
                    items: List.generate(12, (i) => ('$i', '分类$i')),
                    selected: selected,
                    onChanged: (v) => update(() => selected = v),
                  )),
        ))));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(GlassSegmentedControl), const Offset(-1800, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类11').first);
    await tester.pumpAndSettle();
    expect(selected, '11');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search retains focus and query through theme changes; clear and submit propagate',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? edited;
    String? submitted;
    Widget field() => MusicSearchField(
        controller: controller,
        onChanged: (v) => edited = v,
        onSubmitted: (v) => submitted = v);
    await tester.pumpWidget(app(field()));
    await tester.enterText(find.byType(EditableText), '周杰伦');
    await tester.pump();
    expect(edited, '周杰伦');
    await tester.pumpWidget(app(field(), brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(controller.text, '周杰伦');
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(submitted, '周杰伦');
    await tester.tap(find.bySemanticsLabel('清除搜索'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(edited, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'queue glass sheet shares scroll controller and supports delete and clear confirmation',
      (tester) async {
    final player = QueuePlayer();
    addTearDown(player.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<PlayerStore>.value(
      value: player,
      child: app(Builder(
          builder: (context) => TextButton(
              onPressed: () => showAuxSheet(context, const QueueSheet()),
              child: const Text('打开队列')))),
    ));
    await tester.tap(find.text('打开队列'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassModalSheetScaffold), findsOneWidget);
    final list = tester.widget<ListView>(find.byType(ListView));
    final context = tester.element(find.byType(QueueSheet));
    expect(list.controller,
        same(ScrollControllerProvider.of(context)!.controller));
    await tester.tap(find.byTooltip('从队列删除').first);
    await tester.pumpAndSettle();
    expect(player.queue.length, 39);
    expect(player.queue.first.id, '1');
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(list.controller!.offset, greaterThan(0));
    await tester.tap(find.byTooltip('清空队列'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(player.cleared, 0);
    await tester.tap(find.byTooltip('清空队列'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部删除'));
    await tester.pumpAndSettle();
    expect(player.cleared, 1);
    expect(find.text('队列为空'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(QueueSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'track menu dispatches actions and system back closes only the menu',
      (tester) async {
    final player = QueuePlayer();
    final ui = UIStore();
    addTearDown(player.dispose);
    addTearDown(ui.dispose);
    final track = player.queue.first;
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<PlayerStore>.value(value: player),
      ChangeNotifierProvider<UIStore>.value(value: ui),
    ], child: app(Center(child: TrackActionsMenu(track: track)))));
    await tester.tap(find.byTooltip('歌曲操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入队列'));
    await tester.pumpAndSettle();
    expect(player.enqueued, [track]);
    await tester.tap(find.byTooltip('歌曲操作'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(TrackActionsMenu));
    await Navigator.of(context).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('加入队列'), findsNothing);
    expect(find.byType(TrackActionsMenu), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
