import 'package:flutter/services.dart';

import '../local/local_store.dart';
import '../stores/ui_store.dart';

/// One launcher icon variant — mirrors the aliases in AndroidManifest and the
/// `launcherAliases` map in MainActivity.kt.
class AppIconVariant {
  final String id;
  final String name;
  final String subtitle;
  final String previewAsset;

  const AppIconVariant(this.id, this.name, this.subtitle)
      : previewAsset = 'assets/icons/icon_$id.png';

  static const classic =
      AppIconVariant('classic', '经典霓虹', '玻璃唱片 · 霓虹渐变');
  static const midnight = AppIconVariant('midnight', '午夜蓝', '深邃沉浸');
  static const sunset = AppIconVariant('sunset', '落日橙', '温暖醒目');
  static const mint = AppIconVariant('mint', '薄荷青', '清爽明亮');
  static const aurora = AppIconVariant('aurora', '极光紫', '通透未来');
  static const cherry = AppIconVariant('cherry', '樱花粉', '甜美柔和');
  static const mono = AppIconVariant('mono', '黑白工作室', '极简质感');
  static const lime = AppIconVariant('lime', '青柠电波', '活力跃动');

  static const all = <AppIconVariant>[
    classic,
    midnight,
    sunset,
    mint,
    aurora,
    cherry,
    mono,
    lime,
  ];

  static AppIconVariant? byId(String id) {
    for (final variant in all) {
      if (variant.id == id) return variant;
    }
    return null;
  }
}

/// Launcher icon switching via activity-alias component state.
class AppIconService {
  static const _channel = MethodChannel('com.musix.app/app_icon');

  /// Reads the actually-enabled alias from the platform. Falls back to the
  /// cached preference when the channel is unavailable (tests / iOS).
  static Future<String> currentId({String fallback = 'classic'}) async {
    try {
      final id = await _channel.invokeMethod<String>('getCurrent');
      if (id != null && AppIconVariant.byId(id) != null) return id;
    } catch (_) {}
    return fallback;
  }

  /// Applies the new launcher alias on the platform and caches the choice.
  static Future<bool> apply(String id, UIStore ui, LocalStore local) async {
    if (AppIconVariant.byId(id) == null) return false;
    var ok = false;
    try {
      final applied = await _channel
          .invokeMethod<String>('setCurrent', {'id': id});
      ok = applied == id;
    } catch (_) {
      ok = false;
    }
    // Cache regardless so the picker reflects the intent even on platforms
    // without the alias channel.
    ui.setAppIcon(id, local);
    return ok;
  }
}
