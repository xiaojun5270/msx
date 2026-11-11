import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自更新下载线路：直连 GitHub 或经加速源。
///
/// 加速源支持两种写法：
/// - 前缀式 `https://ghfast.top/` → `https://ghfast.top/https://github.com/...`
/// - 占位符式 `https://x/{url}` → 直接把原始地址填进 `{url}`
@immutable
class UpdateMirror {
  const UpdateMirror({
    required this.id,
    required this.label,
    required this.template,
    this.builtin = false,
    this.isDirect = false,
  });

  const UpdateMirror.direct()
      : id = directId,
        label = '直连 GitHub',
        template = '',
        builtin = true,
        isDirect = true;

  static const String directId = 'direct';
  static const String urlPlaceholder = '{url}';

  final String id;
  final String label;

  /// 前缀式（`https://ghproxy.net/`）或占位符式（`https://x/{url}`）。
  final String template;
  final bool builtin;
  final bool isDirect;

  /// 把 GitHub 原始下载地址转换为该线路的实际下载地址。
  String resolve(String sourceUrl) {
    if (isDirect) return sourceUrl;
    final trimmed = template.trim();
    if (trimmed.isEmpty) return sourceUrl;
    if (trimmed.contains(urlPlaceholder)) {
      return trimmed.replaceAll(urlPlaceholder, sourceUrl);
    }
    return trimmed.endsWith('/') ? '$trimmed$sourceUrl' : '$trimmed/$sourceUrl';
  }

  /// 校验用户输入，返回错误文案；合法时返回 null。
  ///
  /// 与 MoviePilotLite 一致：缺协议的裸域名按 https 处理，这样用户直接填
  /// `ghfast.top` 也能通过。
  static String? validateTemplate(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '请输入加速源地址';
    if (!value.contains(urlPlaceholder) && !_hasScheme(value)) {
      value = 'https://$value';
    }
    final sample = value.replaceAll(urlPlaceholder, 'https://example.com/a.apk');
    final uri = Uri.tryParse(sample);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '地址格式不正确';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '仅支持 http/https 地址';
    }
    return null;
  }

  /// 把用户输入规整成可直接保存的模板；非法时返回 null。
  ///
  /// 补全协议、给裸域名补结尾斜杠，避免「能拼出正确地址却被判非法」。
  static String? normalizeTemplate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (validateTemplate(value) != null) return null;
    if (value.contains(urlPlaceholder)) return value;
    final withScheme = _hasScheme(value) ? value : 'https://$value';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.path.isEmpty && !withScheme.endsWith('/')) return '$withScheme/';
    return withScheme;
  }

  static bool _hasScheme(String value) =>
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(value);

  /// 用户未填写名称时，用域名作为展示名。
  static String labelFromTemplate(String raw) {
    final value = raw.trim();
    final sample = value.replaceAll(urlPlaceholder, '');
    final withScheme = _hasScheme(sample) ? sample : 'https://$sample';
    final uri = Uri.tryParse(withScheme);
    final host = uri?.host ?? '';
    return host.isEmpty ? value : host;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'template': template,
      };

  static UpdateMirror? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final template = raw['template']?.toString().trim() ?? '';
    if (id.isEmpty || template.isEmpty) return null;
    final label = raw['label']?.toString().trim() ?? '';
    return UpdateMirror(
      id: id,
      label: label.isEmpty ? labelFromTemplate(template) : label,
      template: template,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UpdateMirror &&
      other.id == id &&
      other.label == label &&
      other.template == template &&
      other.isDirect == isDirect;

  @override
  int get hashCode => Object.hash(id, label, template, isDirect);
}

/// 下载线路的选择状态与自定义线路持久化。
///
/// 单例 + [ChangeNotifier]：设置页与更新弹层共用同一份选择，任何一处切换
/// 另一处立即跟随。
class UpdateMirrorStore extends ChangeNotifier {
  UpdateMirrorStore._();

  static final UpdateMirrorStore instance = UpdateMirrorStore._();

  static const String _selectedKey = 'update_mirror_selected';
  static const String _customKey = 'update_mirror_custom';

  /// 内置加速源，顺序沿用 MoviePilotLite 实测排序，首个为默认候选。
  static const List<UpdateMirror> builtinMirrors = [
    UpdateMirror(
      id: 'gh-proxy-org',
      label: 'gh-proxy.org',
      template: 'https://gh-proxy.org/',
      builtin: true,
    ),
    UpdateMirror(
      id: 'gh-proxy',
      label: 'gh-proxy.com',
      template: 'https://gh-proxy.com/',
      builtin: true,
    ),
    UpdateMirror(
      id: 'ghfast',
      label: 'ghfast.top',
      template: 'https://ghfast.top/',
      builtin: true,
    ),
    UpdateMirror(
      id: 'ghproxy',
      label: 'ghproxy.net',
      template: 'https://ghproxy.net/',
      builtin: true,
    ),
  ];

  String _selectedId = UpdateMirror.directId;
  List<UpdateMirror> _custom = const [];
  bool _loaded = false;
  Future<void>? _loading;

  String get selectedId => _selectedId;
  bool get loaded => _loaded;

  List<UpdateMirror> get customMirrors => List.unmodifiable(_custom);

  List<UpdateMirror> get allMirrors => [
        const UpdateMirror.direct(),
        ...builtinMirrors,
        ..._custom,
      ];

  UpdateMirror get selectedMirror {
    for (final mirror in allMirrors) {
      if (mirror.id == _selectedId) return mirror;
    }
    return const UpdateMirror.direct();
  }

  /// 首次使用时等待偏好读取完成，避免读到默认值。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _custom = _decodeCustom(prefs.getString(_customKey));
      _selectedId = _normalizeSelected(prefs.getString(_selectedKey));
    } catch (_) {
      _custom = const [];
      _selectedId = UpdateMirror.directId;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> select(String id) async {
    await ensureLoaded();
    final normalized = _normalizeSelected(id);
    if (normalized == _selectedId) return;
    _selectedId = normalized;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedKey, normalized);
    } catch (_) {}
  }

  /// 新增自定义加速源；重复或非法地址返回 null。
  Future<UpdateMirror?> addCustom(String template, {String? label}) async {
    await ensureLoaded();
    if (UpdateMirror.validateTemplate(template) != null) return null;
    final normalized = UpdateMirror.normalizeTemplate(template);
    if (normalized == null) return null;
    final exists = allMirrors.any(
      (mirror) => !mirror.isDirect && mirror.template.trim() == normalized,
    );
    if (exists) return null;
    final mirror = UpdateMirror(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      label: (label?.trim().isNotEmpty ?? false)
          ? label!.trim()
          : UpdateMirror.labelFromTemplate(normalized),
      template: normalized,
    );
    _custom = [..._custom, mirror];
    notifyListeners();
    await _persistCustom();
    await select(mirror.id);
    return mirror;
  }

  Future<void> removeCustom(String id) async {
    await ensureLoaded();
    if (!_custom.any((mirror) => mirror.id == id)) return;
    _custom = _custom.where((mirror) => mirror.id != id).toList(growable: false);
    notifyListeners();
    await _persistCustom();
    if (_selectedId == id) await select(UpdateMirror.directId);
  }

  /// 检查更新时按「当前选择 → 直连 → 其余内置源」的顺序尝试。
  List<UpdateMirror> get probeOrder {
    final selected = selectedMirror;
    return [
      if (!selected.isDirect) selected,
      const UpdateMirror.direct(),
      for (final mirror in builtinMirrors)
        if (mirror.id != selected.id) mirror,
      for (final mirror in _custom)
        if (mirror.id != selected.id) mirror,
    ];
  }

  Future<void> _persistCustom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _customKey,
        jsonEncode(_custom.map((mirror) => mirror.toJson()).toList()),
      );
    } catch (_) {}
  }

  String _normalizeSelected(String? id) {
    final value = id?.trim() ?? '';
    if (value.isEmpty) return UpdateMirror.directId;
    final known = allMirrors.any((mirror) => mirror.id == value);
    return known ? value : UpdateMirror.directId;
  }

  List<UpdateMirror> _decodeCustom(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(UpdateMirror.fromJson)
          .whereType<UpdateMirror>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// 测试用：清掉缓存的偏好读取状态。
  @visibleForTesting
  void resetForTest() {
    _selectedId = UpdateMirror.directId;
    _custom = const [];
    _loaded = false;
    _loading = null;
  }
}
