import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musix/local/local_store.dart';
import 'package:musix/services/app_icon.dart';
import 'package:musix/stores/ui_store.dart';

void main() {
  group('AppIconVariant', () {
    test('every variant has unique id and resolvable preview', () {
      final ids = AppIconVariant.all.map((v) => v.id).toSet();
      expect(ids.length, AppIconVariant.all.length);
      expect(ids, containsAll(['classic', 'midnight', 'mono', 'lime']));
      for (final variant in AppIconVariant.all) {
        expect(variant.previewAsset, startsWith('assets/icons/icon_'));
      }
    });

    test('byId resolves known ids and rejects unknown', () {
      expect(AppIconVariant.byId('aurora')?.name, '极光紫');
      expect(AppIconVariant.byId('nope'), isNull);
    });
  });

  group('background tune prefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults are blur 0 / opacity 100', () async {
      final local = await LocalStore.open();
      expect(local.prefs.backgroundBlur, 0);
      expect(local.prefs.backgroundOpacity, 100);
      expect(local.appIcon, 'liquid');
    });

    test('setBackgroundTune persists clamped values', () async {
      final local = await LocalStore.open();
      final ui = UIStore();
      ui.loadAppearance(local);

      ui.setBackgroundTune(12, 85, local);
      expect(ui.backgroundBlur, 12);
      expect(ui.backgroundOpacity, 85);

      final reloaded = await LocalStore.open();
      expect(reloaded.prefs.backgroundBlur, 12);
      expect(reloaded.prefs.backgroundOpacity, 85);
    });

    test('setAppIcon persists selection', () async {
      final local = await LocalStore.open();
      final ui = UIStore();
      ui.loadAppearance(local);

      ui.setAppIcon('aurora', local);
      final reloaded = await LocalStore.open();
      expect(reloaded.appIcon, 'aurora');
    });
  });
}
