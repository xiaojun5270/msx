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

  static const liquid = AppIconVariant('liquid', '液态玻璃', '通透流光');
  static const classic =
      AppIconVariant('classic', '经典霓虹', '霓虹 M · 深蓝夜色');
  static const midnight = AppIconVariant('midnight', '午夜蓝', '深邃沉浸');
  static const sunset = AppIconVariant('sunset', '落日橙', '暖阳白 M');
  static const mint = AppIconVariant('mint', '薄荷青', '清爽明亮');
  static const aurora = AppIconVariant('aurora', '极光紫', '通透未来');
  static const cherry = AppIconVariant('cherry', '樱花粉', '甜美柔和');
  static const mono = AppIconVariant('mono', '黑白工作室', '极简质感');
  static const lime = AppIconVariant('lime', '青柠电波', '活力跃动');
  static const wave = AppIconVariant('wave', '彩虹声浪', '五彩律动');
  static const vinyl = AppIconVariant('vinyl', '复古黑胶', '奶油唱机');
  static const headphones = AppIconVariant('headphones', '霓虹耳机', '夜色律动');
  static const note = AppIconVariant('note', '跳动音符', '清新悦耳');
  static const playglass = AppIconVariant('playglass', '玻璃播放', '液态质感');
  static const eq = AppIconVariant('eq', '潮流均衡器', '电波操控');
  static const cassette = AppIconVariant('cassette', '复古磁带', '80 年代卡带');
  static const mic = AppIconVariant('mic', '舞台麦克风', '人声焦点');
  static const pick = AppIconVariant('pick', '吉他拨片', '弦上流光');
  static const piano = AppIconVariant('piano', '钢琴夜曲', '黑白琴键');
  static const speaker = AppIconVariant('speaker', '重低音炮', '震撼低音');
  static const cd = AppIconVariant('cd', '彩虹光盘', '千禧光泽');
  static const radio = AppIconVariant('radio', '复古收音机', '调频时光');

  /// Ordered for the picker: the shipped default sits first.
  static const all = <AppIconVariant>[
    liquid,
    classic,
    midnight,
    sunset,
    mint,
    aurora,
    cherry,
    mono,
    lime,
    wave,
    vinyl,
    headphones,
    note,
    playglass,
    eq,
    cassette,
    mic,
    pick,
    piano,
    speaker,
    cd,
    radio,
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
  static Future<String> currentId({String fallback = 'liquid'}) async {
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
