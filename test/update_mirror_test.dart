import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musix/services/app_update.dart';
import 'package:musix/services/update_mirror.dart';

void main() {
  const source = 'https://github.com/xiaojun5270/msx/releases/download/x/app.apk';

  group('UpdateMirror.resolve', () {
    test('direct returns the source url untouched', () {
      expect(const UpdateMirror.direct().resolve(source), source);
    });

    test('prefix template is prepended with a single slash', () {
      const mirror = UpdateMirror(
        id: 'ghfast',
        label: 'ghfast.top',
        template: 'https://ghfast.top/',
        builtin: true,
      );
      expect(mirror.resolve(source), 'https://ghfast.top/$source');

      const noSlash = UpdateMirror(
        id: 'p',
        label: 'p',
        template: 'https://ghfast.top',
      );
      expect(noSlash.resolve(source), 'https://ghfast.top/$source');
    });

    test('placeholder template substitutes the whole url', () {
      const mirror = UpdateMirror(
        id: 'p',
        label: 'p',
        template: 'https://proxy.example/{url}?download=1',
      );
      expect(mirror.resolve(source),
          'https://proxy.example/$source?download=1');
    });
  });

  group('UpdateMirror template input', () {
    test('accepts bare hosts and normalizes them', () {
      expect(UpdateMirror.validateTemplate('ghfast.top'), isNull);
      expect(UpdateMirror.normalizeTemplate('ghfast.top'),
          'https://ghfast.top/');
    });

    test('keeps explicit paths and placeholder templates', () {
      expect(UpdateMirror.normalizeTemplate('https://proxy.example/github'),
          'https://proxy.example/github');
      expect(UpdateMirror.normalizeTemplate('https://x.example/{url}'),
          'https://x.example/{url}');
    });

    test('rejects empty and non-http input', () {
      expect(UpdateMirror.validateTemplate('  '), '请输入加速源地址');
      expect(UpdateMirror.validateTemplate('ftp://ghfast.top'), isNotNull);
    });

    test('label falls back to the host', () {
      expect(UpdateMirror.labelFromTemplate('https://gh-proxy.org/'),
          'gh-proxy.org');
    });
  });

  group('version comparison', () {
    test('sequence number decides same major.minor.patch', () {
      // currentVersion is injected at build time; parseVersion works on any
      // text so the comparison helper is exercised directly.
      expect(AppUpdateService.parseVersion('0.8.11(019)'), (0, 8, 11, 19));
      expect(AppUpdateService.parseVersion('MusicX 0.8.11(020)'),
          (0, 8, 11, 20));
      expect(AppUpdateService.parseVersion('no version'), isNull);
    });
  });

  group('UpdateMirrorStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      UpdateMirrorStore.instance.resetForTest();
      await UpdateMirrorStore.instance.select(UpdateMirror.directId);
    });

    test('defaults to direct and exposes builtin routes', () async {
      final store = UpdateMirrorStore.instance;
      await store.ensureLoaded();
      expect(store.selectedId, UpdateMirror.directId);
      expect(store.selectedMirror.isDirect, isTrue);
      expect(store.allMirrors.length, 1 + UpdateMirrorStore.builtinMirrors.length);
      expect(store.allMirrors.first.isDirect, isTrue);
    });

    test('selection persists across a reload', () async {
      final store = UpdateMirrorStore.instance;
      await store.ensureLoaded();
      await store.select('ghfast');
      expect(store.selectedMirror.label, 'ghfast.top');

      store.resetForTest();
      await store.ensureLoaded();
      expect(store.selectedId, 'ghfast');
    });

    test('custom routes are validated, deduplicated and persisted', () async {
      final store = UpdateMirrorStore.instance;
      await store.ensureLoaded();

      final added = await store.addCustom('proxy.example');
      expect(added, isNotNull);
      expect(added!.template, 'https://proxy.example/');
      expect(store.selectedId, added.id);
      expect(store.selectedMirror.label, 'proxy.example');

      // Same address again is rejected.
      expect(await store.addCustom('https://proxy.example/'), isNull);
      // Invalid scheme is rejected.
      expect(await store.addCustom('ftp://proxy.example'), isNull);

      store.resetForTest();
      await store.ensureLoaded();
      expect(store.customMirrors.length, 1);
      expect(store.selectedMirror.label, 'proxy.example');

      await store.removeCustom(store.customMirrors.first.id);
      expect(store.customMirrors, isEmpty);
      // Removing the selected custom route falls back to direct.
      expect(store.selectedId, UpdateMirror.directId);
    });

    test('probe order starts with the selected accelerator, then direct',
        () async {
      final store = UpdateMirrorStore.instance;
      await store.ensureLoaded();
      await store.select('ghfast');
      final order = store.probeOrder;
      expect(order.first.id, 'ghfast');
      expect(order[1].isDirect, isTrue);
      expect(order.where((m) => m.id == 'ghfast').length, 1);
    });
  });
}
