import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musix/stores/session_store.dart';
import 'package:musix/stores/ui_store.dart';
import 'package:musix/views/glass_surfaces.dart';
import 'package:musix/views/login_view.dart';
import 'package:provider/provider.dart';

import 'glass_controls_test.dart' show app;

class LoginSession extends ChangeNotifier implements SessionStore {
  @override
  String baseURL = 'http://localhost';
  @override
  String proxyCookie = '';
  @override
  bool get setupRequired => false;
  String? submittedPassword;
  @override
  Future<void> login({required String password}) async {
    submittedPassword = password;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'glass input dialog preserves result and destructive action styling',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? result;
    await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                    context: context,
                    builder: (context) => MusicGlassDialog(
                          title: const Text('新建歌单'),
                          content: TextField(
                              controller: controller, autofocus: true),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('取消')),
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, controller.text),
                                child: const Text('创建')),
                          ],
                        ));
              },
              child: const Text('新建'),
            ))));
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '我的歌单');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(result, '我的歌单');
    await tester
        .pumpWidget(app(MusicGlassDialog(title: const Text('取消订阅'), actions: [
      TextButton(
          onPressed: () {},
          child: const Text('取消订阅', style: TextStyle(color: Colors.red))),
    ])));
    expect(
        tester
            .widget<GlassDialog>(find.byType(GlassDialog))
            .actions
            .single
            .isDestructive,
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'glass switch respects disabled state and stays outside panel glass layer',
      (tester) async {
    var enabled = false;
    var value = false;
    late StateSetter update;
    await tester.pumpWidget(app(StatefulBuilder(builder: (_, setState) {
      update = setState;
      return Center(
          child: MusicGlassPanel.card(
              child: MusicGlassSwitch(
                  value: value,
                  onChanged:
                      enabled ? (v) => setState(() => value = v) : null)));
    })));
    expect(
        find.ancestor(
            of: find.byType(GlassSwitch),
            matching: find.byType(GlassContainer)),
        findsNothing);
    await tester.tap(find.byType(MusicGlassSwitch));
    await tester.pumpAndSettle();
    expect(value, isFalse);
    update(() => enabled = true);
    await tester.pump();
    await tester.tap(find.byType(MusicGlassSwitch));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'glass slider forwards drag/end and follows external volume updates',
      (tester) async {
    double value = 0.2;
    double? end;
    late StateSetter update;
    await tester.pumpWidget(app(StatefulBuilder(builder: (_, setState) {
      update = setState;
      return Center(
          child: SizedBox(
              width: 300,
              child: MusicGlassSlider(
                  value: value,
                  label: '系统媒体音量',
                  onChanged: (v) => setState(() => value = v),
                  onChangeEnd: (v) => end = v)));
    })));
    await tester.drag(find.byType(GlassSlider), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(value, greaterThan(0.2));
    expect(end, isNotNull);
    update(() => value = 0.1);
    await tester.pumpAndSettle();
    expect(tester.widget<GlassSlider>(find.byType(GlassSlider)).value, 0.1);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'glass app bar keeps back, actions and safe area in $brightness',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(app(
          Builder(
              builder: (context) => TextButton(
                    child: const Text('进入详情'),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                              appBar: MusicGlassAppBar(
                                  title: const Text('详情'),
                                  actions: [
                                    IconButton(
                                        tooltip: '收藏',
                                        onPressed: () => tapped++,
                                        icon: const Icon(Icons.star))
                                  ]),
                              body: const Text('页面内容')),
                        )),
                  )),
          brightness: brightness));
      await tester.tap(find.text('进入详情'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassAppBar), findsOneWidget);
      expect(tester.getTopLeft(find.text('页面内容')).dy, greaterThanOrEqualTo(56));
      await tester.tap(find.byTooltip('收藏'));
      expect(tapped, 1);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('进入详情'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'login glass fields retain next/go focus, visibility and validation in $brightness',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = LoginSession();
      final ui = UIStore();
      addTearDown(session.dispose);
      addTearDown(ui.dispose);
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<SessionStore>.value(value: session),
        ChangeNotifierProvider<UIStore>.value(value: ui),
      ], child: app(const LoginView(), brightness: brightness)));
      await tester.pumpAndSettle();
      final server = find.byType(EditableText).first;
      await tester.enterText(server, 'http://192.168.1.5:8080/');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(session.baseURL, 'http://192.168.1.5:8080');
      final password = find.descendant(
          of: find.byType(GlassPasswordField),
          matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(password).focusNode.hasFocus, isTrue);
      await tester.enterText(password, 'short');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(find.text('密码至少 8 位'), findsOneWidget);
      expect(session.submittedPassword, isNull);
      await tester.tap(find.bySemanticsLabel('显示密码'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(password).obscureText, isFalse);
      await tester.enterText(password, 'test-passphrase');
      await tester.tap(find.bySemanticsLabel('隐藏密码'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(password).obscureText, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(session.submittedPassword, 'test-passphrase');
      expect(
          find.ancestor(
              of: find.byType(GlassPasswordField),
              matching: find.byType(GlassContainer)),
          findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
