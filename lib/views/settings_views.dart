import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/artwork_color.dart';
import '../theme/glass.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';

// ===========================================================================
// Shared building blocks — mirror the private helpers in Swift SettingsViews.
// ===========================================================================

/// Rounded panel used across the settings cards (Swift `settingsMaterialCard`).
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => GlassSurface(
        borderRadius: BorderRadius.circular(16),
        blur: 26,
        tint: const Color.fromRGBO(255, 255, 255, 0.12),
        padding: padding,
        showBorder: true,
        showHighlight: false,
        showShadow: true,
        child: SizedBox(
          width: double.infinity,
          child: child,
        ),
      );
}

/// Text field styled like Swift `settingsField` / `settingsSecure`.
Widget _field(
  TextEditingController controller,
  String placeholder, {
  bool obscure = false,
  TextInputType? keyboardType,
  ValueChanged<String>? onChanged,
}) {
  return TextField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboardType,
    onChanged: onChanged,
    style: TextStyle(color: MX.fg, fontSize: 15),
    cursorColor: MX.ember,
    decoration: InputDecoration(
      hintText: placeholder,
      hintStyle: TextStyle(color: MX.dimSoft, fontSize: 14),
      filled: true,
      fillColor: MX.fillStrong,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: MX.hairline)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: MX.hairline)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: MX.ember.withOpacity(0.6))),
    ),
  );
}

Widget _numberField(TextEditingController controller, String placeholder,
        {ValueChanged<String>? onChanged}) =>
    _field(controller, placeholder,
        keyboardType: TextInputType.number, onChanged: onChanged);

/// Section header row (Swift `SectionHeader`).
Widget _sectionHeader(String title, IconData icon) => Row(
      children: [
        Icon(icon, size: 18, color: MX.ember),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                color: MX.fg, fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );

/// Pill button used inside cards (bordered vs. prominent variants).
Widget _pill(String label, IconData icon, VoidCallback? onPressed,
    {bool filled = false}) {
  final enabled = onPressed != null;
  final bg = filled ? MX.ember : MX.fillStrong;
  final fg = filled ? MX.onAccent : MX.fg;
  return Opacity(
    opacity: enabled ? 1 : 0.45,
    child: Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: filled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MX.hairline)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: fg, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Selectable capsule chip (Swift `MXChip`).
class _MXChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MXChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? MX.ember : MX.fillStrong,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MX.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 12, color: MX.onAccent),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: TextStyle(
                      color: selected ? MX.onAccent : MX.fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

/// Wrap-grid of chips (Swift LazyVGrid of MXChip).
Widget _chipWrap(List<Widget> chips) =>
    Wrap(spacing: 8, runSpacing: 8, children: chips);

/// Standard scaffold for a settings sub-page.
Widget _settingsScaffold(String title, Widget body, {List<Widget>? actions}) =>
    Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: MX.fg,
        elevation: 0,
        title: Text(title,
            style: TextStyle(color: MX.fg, fontWeight: FontWeight.w700)),
        actions: actions,
      ),
      body: body,
    );

// ===========================================================================
// SettingsView — top-level settings list.
// Note: the Swift `iCloudLoginSection` is Apple-only and has no Android
// equivalent, so it is intentionally omitted.
// ===========================================================================

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  static const _platformOrder = [
    'netease',
    'qqmusic',
    'kugou',
    'apple',
    'navidrome',
    'youtube'
  ];

  Map<String, BindingSummary> _bindings = {};
  Map<String, ServiceInfo> _services = {};
  String? _serverVersion;
  PlaylistHealthConfig? _health;
  CookieCloudConfig? _cookie;
  int _subscriptionCount = 0;
  final _backgroundUrls = TextEditingController();

  @override
  void initState() {
    super.initState();
    _backgroundUrls.text =
        context.read<SessionStore>().local.prefs.backgroundImageUrls;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _backgroundUrls.dispose();
    super.dispose();
  }

  void _saveBackgroundUrls(UIStore ui, SessionStore session) {
    if (!ui.setBackgroundImageUrls(_backgroundUrls.text, session.local)) {
      ui.notify('请输入有效的 HTTP 或 HTTPS 图片地址');
      return;
    }
    _backgroundUrls.text = ui.backgroundImageUrls;
    ui.notify(ui.backgroundImageUrl == null ? '已关闭随机背景' : '随机背景已保存');
  }

  Future<void> _reload() async {
    final api = context.read<SessionStore>().api;
    final session = context.read<SessionStore>();
    try {
      final box = await api.getJson('/api/me/bindings', BindingsBox.fromJson);
      _bindings = box.bindings ?? {};
      session.bindings = _bindings;
    } catch (_) {}
    try {
      final box =
          await api.getJson('/api/settings/services', ServicesBox.fromJson);
      _services = box.services ?? {};
    } catch (_) {}
    try {
      _serverVersion =
          (await api.getJson('/api/version', VersionInfo.fromJson)).version;
    } catch (_) {}
    try {
      final box =
          await api.getJson('/api/subscriptions', SubscriptionsBox.fromJson);
      _subscriptionCount = box.items?.length ?? 0;
    } catch (_) {}
    try {
      _health = await api.getJson(
          '/api/settings/playlist-health', PlaylistHealthConfig.fromJson);
    } catch (_) {}
    try {
      _cookie = await api.getJson('/api/settings/services/cookiecloud/config',
          CookieCloudConfig.fromJson);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  String get _appVersion => '1.0.0';

  String get _serverSubtitle {
    final uri = Uri.tryParse(context.read<SessionStore>().baseURL);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    }
    return context.read<SessionStore>().baseURL;
  }

  String get _automationSubtitle {
    final parts = <String>[];
    if (_subscriptionCount > 0) parts.add('$_subscriptionCount 个订阅');
    if (_health?.enabled == true) parts.add('体检开启');
    if (_cookie?.enabled == true) parts.add('CookieCloud 开启');
    return parts.isEmpty ? '订阅、体检、CookieCloud、限流' : parts.join(' · ');
  }

  String _platformSubtitle(String id) {
    final b = _bindings[id];
    if (b != null && b.bound == true) return b.displayName;
    final s = _services[id];
    if (s?.effectiveUrl != null && s!.effectiveUrl!.isNotEmpty)
      return s.effectiveUrl!;
    if (id == 'youtube') return '未配置';
    return '未绑定';
  }

  void _open(AppRoute route) => context.read<UIStore>().open(route);

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('退出登录？', style: TextStyle(color: MX.fg)),
        content: Text('将清除本机会话并返回登录页。', style: TextStyle(color: MX.dim)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消', style: TextStyle(color: MX.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出登录',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<SessionStore>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final ui = context.watch<UIStore>();
    return _settingsScaffold(
      '设置',
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _group(
            header: '账户',
            rows: [
              _accountRow(session.nickname, session.avatarUrl, '个人资料、头像与音乐空间',
                  () => _open(SimpleRoute.settingsProfile)),
            ],
          ),
          _appearanceGroup(ui, session),
          _group(
            header: '自动化',
            rows: [
              _navRow(
                  Icons.settings_suggest,
                  '自动化',
                  _automationSubtitle,
                  const Color(0xFF73787F),
                  () => _open(SimpleRoute.settingsAutomation)),
            ],
          ),
          _group(
            header: '平台',
            rows: [
              for (final id in _platformOrder) _platformRow(id),
            ],
          ),
          _group(
            header: '音源',
            rows: [
              _navRow(Icons.graphic_eq, 'LX 自定义音源', '管理脚本、启用状态与支持平台',
                  MX.tone('lx'), () => _open(SimpleRoute.settingsSources)),
            ],
          ),
          _group(
            header: '诊断',
            rows: [
              _navRow(Icons.manage_search, '服务日志', '排查服务端错误与请求状态',
                  const Color(0xFFFF9500), () => _open(SimpleRoute.serverLogs)),
              _divider(),
              _navRow(Icons.description, '客户端日志', '本机播放与应用日志，可导出分享',
                  const Color(0xFF8C59F2), () => _open(SimpleRoute.clientLogs)),
            ],
          ),
          _group(
            header: '关于',
            rows: [
              _aboutRow(Icons.dns, '服务端', _serverSubtitle,
                  _serverVersion ?? '—', MX.ember),
              _divider(),
              _aboutRow(Icons.phone_iphone, '客户端', '', _appVersion,
                  const Color(0xFF598CF2)),
            ],
          ),
          const SizedBox(height: 8),
          _Card(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: TextButton(
              onPressed: _confirmLogout,
              child: const Text('退出登录',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // -- section + row builders -----------------------------------------------

  Widget _group({String? header, String? footer, required List<Widget> rows}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(header,
                    style: TextStyle(
                        color: MX.mute,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            _Card(padding: EdgeInsets.zero, child: Column(children: rows)),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 8),
                child: Text(footer,
                    style: TextStyle(color: MX.mute, fontSize: 12)),
              ),
          ],
        ),
      );

  Widget _divider() => Padding(
        padding: const EdgeInsets.only(left: 58),
        child: Divider(height: 1, color: MX.line),
      );

  Widget _accountRow(
          String name, String? avatar, String subtitle, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CoverArt(src: avatar, size: 46, circle: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: MX.fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MX.mute, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: MX.dimSoft),
            ],
          ),
        ),
      );

  Widget _navRow(IconData icon, String title, String subtitle, Color tint,
          VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: tint, borderRadius: BorderRadius.circular(7)),
                child: Icon(icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: MX.fg, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MX.mute, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: MX.dimSoft),
            ],
          ),
        ),
      );

  Widget _platformRow(String id) {
    final bound = _bindings[id]?.bound == true;
    final tone = MX.tone(id);
    return InkWell(
      onTap: () => _open(SettingsPlatformRoute(id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: tone.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(7)),
              child: Icon(MX.icon(id), size: 16, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(MX.label(id),
                      style: TextStyle(color: MX.fg, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(_platformSubtitle(id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MX.mute, fontSize: 12)),
                ],
              ),
            ),
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                  color: bound ? tone : MX.dimSoft, shape: BoxShape.circle),
            ),
            Text(bound ? '已连接' : '未连接',
                style: TextStyle(color: MX.mute, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _aboutRow(IconData icon, String title, String subtitle,
          String trailing, Color tint) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: tint, borderRadius: BorderRadius.circular(7)),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: MX.fg, fontSize: 15)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MX.mute, fontSize: 12)),
                  ],
                ],
              ),
            ),
            Text(trailing,
                style: TextStyle(
                    color: MX.mute,
                    fontSize: 14,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      );

  Widget _appearanceGroup(UIStore ui, SessionStore session) => _group(
        header: '外观与主题',
        rows: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                    child: Text('显示模式',
                        style: TextStyle(color: MX.fg, fontSize: 15))),
                DropdownButtonHideUnderline(
                  child: DropdownButton<AppearanceMode>(
                    value: ui.appearance,
                    dropdownColor: MX.panel,
                    style: TextStyle(color: MX.fg, fontSize: 14),
                    icon: Icon(Icons.expand_more, color: MX.mute, size: 18),
                    items: [
                      for (final m in AppearanceMode.values)
                        DropdownMenuItem(
                            value: m,
                            child:
                                Text(m.title, style: TextStyle(color: MX.fg))),
                    ],
                    onChanged: (m) {
                      if (m != null) ui.setAppearance(m, session.local);
                    },
                  ),
                ),
              ],
            ),
          ),
          _divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette, size: 16, color: MX.fg),
                    const SizedBox(width: 8),
                    Text('主题色', style: TextStyle(color: MX.fg, fontSize: 15)),
                    const Spacer(),
                    Text(ui.themeAccent.title,
                        style: TextStyle(
                            color: ui.themeAccent.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final accent in ThemeAccent.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _accentSwatch(accent, ui.themeAccent == accent,
                            () => ui.setThemeAccent(accent, session.local)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('用于播放、选中状态和主要操作；更换后立即生效。',
                    style: TextStyle(color: MX.mute, fontSize: 12)),
              ],
            ),
          ),
          _divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.wallpaper_rounded, size: 17, color: MX.fg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('随机背景图 URL',
                          style: TextStyle(color: MX.fg, fontSize: 15)),
                    ),
                    IconButton(
                      tooltip: '换一张',
                      visualDensity: VisualDensity.compact,
                      onPressed: ui.backgroundImageUrl == null
                          ? null
                          : ui.shuffleBackground,
                      icon: Icon(Icons.shuffle_rounded,
                          size: 19, color: MX.ember),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _backgroundUrls,
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: TextStyle(color: MX.fg, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://image.example.com/random.jpg',
                    hintStyle: TextStyle(color: MX.dimSoft, fontSize: 12),
                    filled: true,
                    fillColor: MX.fillStrong,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: MX.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: MX.hairline),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: Text('支持随机图片接口；多个图床直链可分行填写。',
                          style: TextStyle(color: MX.mute, fontSize: 11.5)),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () => _saveBackgroundUrls(ui, session),
                      style: FilledButton.styleFrom(
                        backgroundColor: MX.ember,
                        foregroundColor: MX.onAccent,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

  Widget _accentSwatch(ThemeAccent accent, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? accent.color : Colors.transparent, width: 2),
          ),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.4)),
            ),
            child: selected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        ),
      );
}

// ===========================================================================
// ProfileSettingsView — nickname + avatar management.
// ===========================================================================

class ProfileSettingsView extends StatefulWidget {
  const ProfileSettingsView({super.key});
  @override
  State<ProfileSettingsView> createState() => _ProfileSettingsViewState();
}

class _ProfileSettingsViewState extends State<ProfileSettingsView> {
  final _nickname = TextEditingController();
  final _avatarLink = TextEditingController();
  bool _useLink = false;
  bool _saving = false;
  bool _uploading = false;
  String? _pendingAvatarUrl; // set after upload or via link; null = unchanged

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionStore>();
    _nickname.text = session.nickname == 'Musix' ? '' : session.nickname;
    _avatarLink.text = session.avatarUrl ?? '';
  }

  @override
  void dispose() {
    _nickname.dispose();
    _avatarLink.dispose();
    super.dispose();
  }

  bool get _canSave {
    final name = _nickname.text.trim();
    return name.isNotEmpty && name.length <= 32 && !_saving && !_uploading;
  }

  String get _displayName {
    final name = _nickname.text.trim();
    return name.isEmpty ? 'Musix' : name;
  }

  String? get _previewAvatar {
    if (_pendingAvatarUrl != null) return _pendingAvatarUrl;
    if (_useLink && _avatarLink.text.trim().isNotEmpty)
      return _avatarLink.text.trim();
    return context.read<SessionStore>().avatarUrl;
  }

  ({String ext, String mime})? _detect(List<int> b) {
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return (ext: 'png', mime: 'image/png');
    }
    if (b.length >= 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return (ext: 'gif', mime: 'image/gif');
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return (ext: 'webp', mime: 'image/webp');
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return (ext: 'jpg', mime: 'image/jpeg');
    }
    return null;
  }

  Future<void> _pickAndUpload() async {
    final ui = context.read<UIStore>();
    final api = context.read<SessionStore>().api;
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 92);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        ui.notify('图片超过 20 MB');
        return;
      }
      final kind = _detect(bytes);
      if (kind == null) {
        ui.notify('不支持的图片格式');
        return;
      }
      setState(() => _uploading = true);
      final url = await api.upload<String>(
        '/api/me/profile/avatar/upload',
        data: bytes,
        filename: 'avatar.${kind.ext}',
        mimeType: kind.mime,
        factory: (m) => m['url']?.toString() ?? '',
      );
      if (!mounted) return;
      setState(() {
        _pendingAvatarUrl = url.isEmpty ? null : url;
        _uploading = false;
      });
      ui.notify('头像上传成功，保存后生效');
    } catch (e) {
      if (mounted) setState(() => _uploading = false);
      ui.notify('$e');
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    setState(() => _saving = true);
    try {
      String? avatar;
      if (_pendingAvatarUrl != null) {
        avatar = _pendingAvatarUrl;
      } else if (_useLink) {
        avatar = _avatarLink.text.trim();
      }
      final body = <String, dynamic>{'nickname': _nickname.text.trim()};
      if (avatar != null) body['avatarUrl'] = avatar;
      await session.api.put('/api/me/profile', json: body);
      await session.bootstrap();
      if (!mounted) return;
      setState(() => _saving = false);
      ui.notify('已保存');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      ui.notify('$e');
    }
  }

  Future<void> _removeAvatar() async {
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      await session.api.put('/api/me/profile',
          json: {'nickname': _nickname.text.trim(), 'avatarUrl': ''});
      await session.bootstrap();
      if (!mounted) return;
      setState(() {
        _pendingAvatarUrl = null;
        _avatarLink.text = '';
      });
      ui.notify('已移除头像');
    } catch (e) {
      ui.notify('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _settingsScaffold(
      '个人资料',
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Card(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: MX.ember, width: 2),
                  ),
                  child: CoverArt(src: _previewAvatar, size: 88, circle: true),
                ),
                const SizedBox(height: 12),
                Text(_displayName,
                    style: TextStyle(
                        color: MX.fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('个人音乐空间', style: TextStyle(color: MX.mute, fontSize: 13)),
                const SizedBox(height: 14),
                _pill(_uploading ? '正在上传…' : '更换头像', Icons.photo_library,
                    _uploading ? null : _pickAndUpload,
                    filled: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('昵称', Icons.badge),
                const SizedBox(height: 10),
                _field(_nickname, '昵称', onChanged: (_) => setState(() {})),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => setState(() => _useLink = !_useLink),
                  child: Row(
                    children: [
                      Icon(_useLink ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: MX.mute),
                      const SizedBox(width: 6),
                      Text('使用图片链接',
                          style: TextStyle(color: MX.fg, fontSize: 14)),
                    ],
                  ),
                ),
                if (_useLink) ...[
                  const SizedBox(height: 10),
                  _field(_avatarLink, '头像链接',
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setState(() {})),
                ],
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _removeAvatar,
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.redAccent),
                    label: const Text('移除头像',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('昵称最多 32 个字符。头像支持常见图片格式，最大 20 MB。',
              style: TextStyle(color: MX.mute, fontSize: 12)),
          const SizedBox(height: 20),
          _pill(_saving ? '保存中…' : '完成', Icons.check, _canSave ? _save : null,
              filled: true),
        ],
      ),
    );
  }
}

// ===========================================================================
// AutomationView — CookieCloud + playlist health + ingest throttle.
// ===========================================================================

class AutomationView extends StatefulWidget {
  const AutomationView({super.key});
  @override
  State<AutomationView> createState() => _AutomationViewState();
}

class _AutomationViewState extends State<AutomationView> {
  static const _cryptoOptions = [
    ('auto', '自动识别'),
    ('aes-128-cbc-fixed', 'AES-128-CBC Fixed IV'),
    ('legacy', 'Legacy CryptoJS'),
  ];
  static const _bitrateOptions = [
    (0, '不筛选'),
    (128000, '128k 及以上'),
    (192000, '192k 及以上'),
    (320000, '320k 及以上'),
  ];
  static const _healthPlatformOrder = [
    'navidrome',
    'netease',
    'qqmusic',
    'kugou'
  ];

  // CookieCloud
  final _ccUrl = TextEditingController();
  final _ccUuid = TextEditingController();
  final _ccPass = TextEditingController();
  final _ccRefresh = TextEditingController();
  String _ccCrypto = 'auto';
  bool _ccEnabled = false;
  bool _ccPasswordConfigured = false;
  bool _ccSaving = false, _ccTesting = false;
  String? _ccCaption, _ccError;

  // Health
  final _healthCron = TextEditingController();
  int _minBitrate = 0;
  bool _preferLossless = false;
  bool _healthEnabled = false;
  final Set<String> _healthPlatforms = {};
  bool _healthSaving = false, _healthRunning = false;
  String? _healthSummaryCaption;

  // Throttle
  final _concurrency = TextEditingController();
  final _gapMs = TextEditingController();
  bool _throttleSaving = false;
  String? _throttleRangeCaption;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    for (final c in [
      _ccUrl,
      _ccUuid,
      _ccPass,
      _ccRefresh,
      _healthCron,
      _concurrency,
      _gapMs
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    final api = context.read<SessionStore>().api;
    try {
      final ing =
          await api.getJson('/api/settings/ingest', IngestSettings.fromJson);
      _concurrency.text = (ing.concurrency ?? 0).round().toString();
      _gapMs.text = (ing.gapMs ?? 0).round().toString();
      final cr = ing.limits?.concurrency, gr = ing.limits?.gapMs;
      if (cr != null && gr != null) {
        _throttleRangeCaption = '并发 ${_fmtRange(cr)} · 间隔 ${_fmtRange(gr)} 毫秒';
      }
    } catch (_) {}
    try {
      final h = await api.getJson(
          '/api/settings/playlist-health', PlaylistHealthConfig.fromJson);
      _healthEnabled = h.enabled ?? false;
      _healthCron.text = h.cron ?? '';
      _minBitrate = (h.minBitrate ?? 0).round();
      _preferLossless = h.preferLossless ?? false;
      _healthPlatforms
        ..clear()
        ..addAll(h.replacementPlatforms ?? const []);
      final s = h.lastSummary;
      if (s != null) {
        _healthSummaryCaption =
            '上次体检：检查 ${(s.checked ?? 0).round()} · 失效 ${(s.unavailable ?? 0).round()} · 会员 ${(s.vip ?? 0).round()} · 低质 ${(s.lowQuality ?? 0).round()}';
      }
    } catch (_) {}
    try {
      final cc = await api.getJson('/api/settings/services/cookiecloud/config',
          CookieCloudConfig.fromJson);
      _ccEnabled = cc.enabled ?? false;
      _ccUrl.text = cc.url ?? '';
      _ccUuid.text = cc.uuid ?? '';
      _ccCrypto = cc.cryptoType ?? 'auto';
      _ccPasswordConfigured = cc.passwordConfigured ?? false;
      _ccRefresh.text = (cc.refreshSeconds ?? 0).round().toString();
      _ccError = cc.lastError;
      final parts = <String>[];
      if (cc.lastSyncAt != null && cc.lastSyncAt!.isNotEmpty) {
        final t = cc.lastSyncAt!;
        parts.add(
            '上次同步 ${t.length > 16 ? t.substring(0, 16).replaceAll('T', ' ') : t.replaceAll('T', ' ')}');
      }
      if (cc.lastCookieCount != null)
        parts.add('${cc.lastCookieCount} 条 Cookie');
      _ccCaption = parts.isEmpty ? null : parts.join(' · ');
    } catch (_) {}
    if (mounted) setState(() {});
  }

  String _fmtRange(IngestRange r) =>
      '${(r.min ?? 0).round()}–${(r.max ?? 0).round()}';

  UIStore get _ui => context.read<UIStore>();
  APIClient get _api => context.read<SessionStore>().api;

  // -- CookieCloud actions ---------------------------------------------------

  Future<void> _ccTest() async {
    setState(() => _ccTesting = true);
    try {
      final res = await _api.postJson<({int count, String crypto})>(
        '/api/settings/services/cookiecloud/test',
        (m) => (
          count: (m['cookieCount'] as num?)?.toInt() ?? 0,
          crypto: m['cryptoType']?.toString() ?? ''
        ),
        json: _ccBody(includePassword: true),
      );
      if (!mounted) return;
      setState(() => _ccTesting = false);
      _ui.notify('同步成功 · ${res.count} 条 Cookie');
      _reload();
    } catch (e) {
      if (mounted) setState(() => _ccTesting = false);
      _ui.notify('$e');
    }
  }

  Future<void> _ccSave() async {
    setState(() => _ccSaving = true);
    try {
      await _api.put('/api/settings/services/cookiecloud/config',
          json: _ccBody(includePassword: true));
      if (!mounted) return;
      setState(() => _ccSaving = false);
      _ui.notify('已保存');
      _reload();
    } catch (e) {
      if (mounted) setState(() => _ccSaving = false);
      _ui.notify('$e');
    }
  }

  Map<String, dynamic> _ccBody({bool includePassword = false}) {
    final body = <String, dynamic>{
      'enabled': _ccEnabled,
      'url': _ccUrl.text.trim(),
      'uuid': _ccUuid.text.trim(),
      'cryptoType': _ccCrypto,
      'refreshSeconds': int.tryParse(_ccRefresh.text.trim()) ?? 0,
    };
    if (includePassword && _ccPass.text.isNotEmpty)
      body['password'] = _ccPass.text;
    return body;
  }

  Future<void> _ccClear() async {
    final ok =
        await _confirm('清除 CookieCloud 配置？', '将删除已保存的 CookieCloud 同步设置。');
    if (ok != true) return;
    try {
      await _api.delete('/api/settings/services/cookiecloud/config');
      if (!mounted) return;
      setState(() {
        _ccEnabled = false;
        _ccUrl.clear();
        _ccUuid.clear();
        _ccPass.clear();
        _ccPasswordConfigured = false;
        _ccCaption = null;
        _ccError = null;
      });
      _ui.notify('已清除');
    } catch (e) {
      _ui.notify('$e');
    }
  }

  // -- Health actions --------------------------------------------------------

  Future<void> _healthRun() async {
    setState(() => _healthRunning = true);
    try {
      await _api.post('/api/settings/playlist-health/run');
      if (!mounted) return;
      setState(() => _healthRunning = false);
      _ui.notify('已开始体检');
      _reload();
    } catch (e) {
      if (mounted) setState(() => _healthRunning = false);
      _ui.notify('$e');
    }
  }

  Future<void> _healthSave() async {
    setState(() => _healthSaving = true);
    try {
      await _api.put('/api/settings/playlist-health', json: {
        'enabled': _healthEnabled,
        'cron': _healthCron.text.trim(),
        'minBitrate': _minBitrate,
        'preferLossless': _preferLossless,
        'replacementPlatforms': _healthPlatforms.toList(),
      });
      if (!mounted) return;
      setState(() => _healthSaving = false);
      _ui.notify('已保存');
    } catch (e) {
      if (mounted) setState(() => _healthSaving = false);
      _ui.notify('$e');
    }
  }

  // -- Throttle actions ------------------------------------------------------

  Future<void> _throttleSave() async {
    setState(() => _throttleSaving = true);
    try {
      await _api.put('/api/settings/ingest', json: {
        'concurrency': int.tryParse(_concurrency.text.trim()) ?? 0,
        'gapMs': int.tryParse(_gapMs.text.trim()) ?? 0,
      });
      if (!mounted) return;
      setState(() => _throttleSaving = false);
      _ui.notify('已保存');
    } catch (e) {
      if (mounted) setState(() => _throttleSaving = false);
      _ui.notify('$e');
    }
  }

  Future<bool?> _confirm(String title, String message) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: MX.panel,
          title: Text(title, style: TextStyle(color: MX.fg)),
          content: Text(message, style: TextStyle(color: MX.dim)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('取消', style: TextStyle(color: MX.dim))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确定',
                    style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      );

  // __APPEND_AUTOMATION_BUILD__
  @override
  Widget build(BuildContext context) {
    return _settingsScaffold(
      '自动化',
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _cookieCloudCard(),
          const SizedBox(height: 16),
          _healthCard(),
          const SizedBox(height: 16),
          _throttleCard(),
        ],
      ),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) =>
      Row(
        children: [
          Expanded(
              child: Text(label, style: TextStyle(color: MX.fg, fontSize: 15))),
          Switch(
            value: value,
            activeColor: MX.ember,
            onChanged: onChanged,
          ),
        ],
      );

  Widget _cookieCloudCard() => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('CookieCloud', Icons.cloud_sync),
            const SizedBox(height: 12),
            _toggleRow(
                '启用同步', _ccEnabled, (v) => setState(() => _ccEnabled = v)),
            const SizedBox(height: 10),
            _field(_ccUrl, 'http://cookiecloud:8088',
                keyboardType: TextInputType.url),
            const SizedBox(height: 10),
            _field(_ccUuid, 'UUID / 用户 KEY'),
            const SizedBox(height: 10),
            _field(_ccPass, _ccPasswordConfigured ? '密码已保存，留空保持不变' : '端到端加密密码',
                obscure: true),
            const SizedBox(height: 12),
            _dropdown<String>('加密格式', _ccCrypto, _cryptoOptions,
                (v) => setState(() => _ccCrypto = v)),
            const SizedBox(height: 10),
            _numberField(_ccRefresh, '刷新间隔（秒）'),
            if (_ccCaption != null) ...[
              const SizedBox(height: 10),
              Text(_ccCaption!, style: TextStyle(color: MX.mute, fontSize: 12)),
            ],
            if (_ccError != null && _ccError!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_ccError!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            _chipWrap([
              _pill('清除', Icons.delete_outline, _ccClear),
              _pill(_ccTesting ? '同步中…' : '测试', Icons.sync,
                  _ccTesting ? null : _ccTest),
              _pill(_ccSaving ? '保存中…' : '保存', Icons.check,
                  _ccSaving ? null : _ccSave,
                  filled: true),
            ]),
          ],
        ),
      );

  Widget _healthCard() => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('歌单体检', Icons.health_and_safety),
            const SizedBox(height: 12),
            _toggleRow('定时体检', _healthEnabled,
                (v) => setState(() => _healthEnabled = v)),
            const SizedBox(height: 10),
            _field(_healthCron, 'Cron 表达式，如 0 4 * * *'),
            const SizedBox(height: 12),
            _dropdown<int>('最低码率', _minBitrate, _bitrateOptions,
                (v) => setState(() => _minBitrate = v)),
            const SizedBox(height: 6),
            _toggleRow('优先无损', _preferLossless,
                (v) => setState(() => _preferLossless = v)),
            const SizedBox(height: 12),
            Text('换源候选平台',
                style: TextStyle(
                    color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _chipWrap([
              for (final id in _healthPlatformOrder)
                _MXChip(
                  label: MX.label(id),
                  selected: _healthPlatforms.contains(id),
                  onTap: () => setState(() => _healthPlatforms.contains(id)
                      ? _healthPlatforms.remove(id)
                      : _healthPlatforms.add(id)),
                ),
            ]),
            if (_healthSummaryCaption != null) ...[
              const SizedBox(height: 12),
              Text(_healthSummaryCaption!,
                  style: TextStyle(color: MX.mute, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            _chipWrap([
              _pill(_healthRunning ? '体检中…' : '立即体检', Icons.play_arrow,
                  _healthRunning ? null : _healthRun),
              _pill(_healthSaving ? '保存中…' : '保存', Icons.check,
                  _healthSaving ? null : _healthSave,
                  filled: true),
            ]),
          ],
        ),
      );

  Widget _throttleCard() => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('入库限流', Icons.speed),
            const SizedBox(height: 12),
            _numberField(_concurrency, '并发数'),
            const SizedBox(height: 10),
            _numberField(_gapMs, '任务间隔（毫秒）'),
            if (_throttleRangeCaption != null) ...[
              const SizedBox(height: 10),
              Text(_throttleRangeCaption!,
                  style: TextStyle(color: MX.mute, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: _pill(_throttleSaving ? '保存中…' : '保存', Icons.check,
                  _throttleSaving ? null : _throttleSave,
                  filled: true),
            ),
          ],
        ),
      );

  Widget _dropdown<T>(String label, T value, List<(T, String)> options,
          ValueChanged<T> onChanged) =>
      Row(
        children: [
          Expanded(
              child: Text(label, style: TextStyle(color: MX.fg, fontSize: 15))),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              dropdownColor: MX.panel,
              style: TextStyle(color: MX.fg, fontSize: 14),
              icon: Icon(Icons.expand_more, color: MX.mute, size: 18),
              items: [
                for (final o in options)
                  DropdownMenuItem(
                      value: o.$1,
                      child: Text(o.$2, style: TextStyle(color: MX.fg))),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      );
}

// ===========================================================================
// PlatformSettingsView — per-platform binding, service URL, ingest, schedule.
// ===========================================================================

class PlatformSettingsView extends StatefulWidget {
  final String id;
  const PlatformSettingsView({super.key, required this.id});
  @override
  State<PlatformSettingsView> createState() => _PlatformSettingsViewState();
}

class _PlatformSettingsViewState extends State<PlatformSettingsView> {
  static const _taskCatalog = [
    ('charts', '榜单'),
    ('chartDetail', '榜单详情'),
    ('recommend', '推荐'),
    ('library', '资料库'),
    ('favorites', '收藏列表'),
    ('details', '二级页缓存'),
  ];

  String get id => widget.id;
  bool get _supportsBinding => id != 'youtube';
  bool get _supportsIngest => id.isNotEmpty;

  BindingSummary? _binding;
  ServiceInfo? _service;
  ScheduleRow? _schedule;

  // bind editor fields
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _cookie = TextEditingController();
  final _appleToken = TextEditingController();
  final _username = TextEditingController();
  bool _binding_saving = false;

  // service
  final _serviceUrl = TextEditingController();
  bool _serviceSaving = false, _serviceTesting = false;

  // ingest (kugou only extras)
  final _kugouGap = TextEditingController();
  final _kugouApiGap = TextEditingController();
  bool _ingestSaving = false;
  String? _kugouRangeCaption;

  // schedule
  final _schCron = TextEditingController();
  final _schTtl = TextEditingController();
  final _schChartLimit = TextEditingController();
  final Set<String> _schTasks = {};
  bool _schEnabled = false, _schSaving = false, _schRunning = false;

  // QR state
  Timer? _qrTimer;
  bool _qrActive = false;
  String? _qrUnikey;
  String? _qrImg;
  String? _qrMessage;
  QRLoginType? _qrLoginType;
  double _qrDeadline = 0;
  int _qrRetries = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    for (final c in [
      _account,
      _password,
      _cookie,
      _appleToken,
      _username,
      _serviceUrl,
      _kugouGap,
      _kugouApiGap,
      _schCron,
      _schTtl,
      _schChartLimit,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  UIStore get _ui => context.read<UIStore>();
  APIClient get _api => context.read<SessionStore>().api;

  Future<void> _reload() async {
    try {
      final box = await _api.getJson('/api/me/bindings', BindingsBox.fromJson);
      _binding = (box.bindings ?? {})[id];
    } catch (_) {}
    try {
      final box =
          await _api.getJson('/api/settings/services', ServicesBox.fromJson);
      _service = (box.services ?? {})[id];
      _serviceUrl.text = _service?.customUrl ?? '';
    } catch (_) {}
    try {
      final ing =
          await _api.getJson('/api/settings/ingest', IngestSettings.fromJson);
      _kugouGap.text = (ing.kugouGapMs ?? 0).round().toString();
      _kugouApiGap.text = (ing.kugouApiGapMs ?? 0).round().toString();
      final gr = ing.limits?.kugouGapMs, ar = ing.limits?.kugouApiGapMs;
      if (gr != null && ar != null) {
        _kugouRangeCaption =
            '任务 ${(gr.min ?? 0).round()}–${(gr.max ?? 0).round()} · API ${(ar.min ?? 0).round()}–${(ar.max ?? 0).round()} 毫秒';
      }
    } catch (_) {}
    try {
      final box =
          await _api.getJson('/api/settings/schedules', SchedulesBox.fromJson);
      _schedule =
          _firstWhere(box.schedules ?? const [], (s) => s.platform == id);
      final s = _schedule;
      if (s != null) {
        _schEnabled = s.enabled ?? false;
        _schCron.text = s.cron ?? '';
        _schTtl.text = (s.ttlSeconds ?? 0).round().toString();
        _schChartLimit.text = (s.chartLimit ?? 0).round().toString();
        _schTasks
          ..clear()
          ..addAll(s.tasks ?? const []);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  static ScheduleRow? _firstWhere(
      List<ScheduleRow> list, bool Function(ScheduleRow) test) {
    for (final e in list) {
      if (test(e)) return e;
    }
    return null;
  }

  // -- QR login state machine ------------------------------------------------

  double _now() => DateTime.now().millisecondsSinceEpoch.toDouble();

  Future<void> _startQr({QRLoginType? loginType}) async {
    _stopQr();
    setState(() {
      _qrActive = true;
      _qrImg = null;
      _qrMessage = '正在生成二维码…';
      _qrLoginType = loginType;
      _qrRetries = 0;
    });
    try {
      var path = '/api/bindings/$id/qr';
      if (id == 'qqmusic' && loginType != null) {
        path +=
            '?loginType=${loginType == QRLoginType.wechat ? 'wechat' : 'qq'}';
      }
      final start = await _api.getJson(path, QRStart.fromJson);
      final serverExp = (start.expiresAt ?? 0) / 1000.0;
      final localExp = _now() / 1000.0 + 180;
      _qrDeadline = serverExp > 0 ? math.min(serverExp, localExp) : localExp;
      if (!mounted) return;
      setState(() {
        _qrUnikey = start.unikey;
        _qrImg = start.qrimg;
        _qrLoginType = start.loginType ?? loginType;
        _qrMessage = start.message ?? '请使用 App 扫码';
      });
      _scheduleQrPoll(clampDelay(start.retryAfterMs));
    } catch (e) {
      if (mounted) setState(() => _qrMessage = '$e');
    }
  }

  double clampDelay(double? ms) {
    final v = (ms ?? 2000).clamp(1000, 10000);
    return v / 1000.0;
  }

  void _scheduleQrPoll(double seconds) {
    _qrTimer?.cancel();
    _qrTimer = Timer(Duration(milliseconds: (seconds * 1000).round()), _pollQr);
  }

  Future<void> _pollQr() async {
    if (!_qrActive || _qrUnikey == null) return;
    if (_now() / 1000.0 > _qrDeadline) {
      _handleExpired();
      return;
    }
    try {
      final encoded = Uri.encodeQueryComponent(_qrUnikey!);
      final poll = await _api.getJson(
          '/api/bindings/$id/poll?unikey=$encoded', QRPoll.fromJson);
      _qrRetries = 0;
      if (poll.done == true) {
        _stopQr();
        if (mounted) setState(() => _qrActive = false);
        _ui.notify('已绑定');
        _reload();
        return;
      }
      if (poll.expired == true) {
        _handleExpired();
        return;
      }
      if (poll.cancelled == true) {
        if (mounted) setState(() => _qrMessage = '已取消');
        _stopQr();
        return;
      }
      if (poll.message != null && mounted)
        setState(() => _qrMessage = poll.message);
      _scheduleQrPoll(clampDelay(poll.retryAfterMs));
    } on ApiError catch (e) {
      if ((e.status == 0 || e.status == 429 || e.status >= 500) &&
          _qrRetries < 3) {
        _qrRetries++;
        _scheduleQrPoll((1 << _qrRetries).toDouble());
      } else {
        if (mounted) setState(() => _qrMessage = '$e');
        _stopQr();
      }
    } catch (e) {
      if (mounted) setState(() => _qrMessage = '$e');
      _stopQr();
    }
  }

  void _handleExpired() {
    if (id == 'netease') {
      _startQr(loginType: _qrLoginType);
    } else {
      if (mounted) setState(() => _qrMessage = '二维码已过期，请重试');
      _stopQr();
    }
  }

  void _stopQr() {
    _qrTimer?.cancel();
    _qrTimer = null;
    if (id == 'qqmusic' && _qrUnikey != null) {
      _api.post('/api/bindings/qqmusic/qr/cancel',
          json: {'unikey': _qrUnikey}).catchError((_) {});
    }
  }

  void _closeQr() {
    _stopQr();
    setState(() => _qrActive = false);
  }

  // -- bind / unbind ---------------------------------------------------------

  Future<void> _bind(Map<String, dynamic> body) async {
    setState(() => _binding_saving = true);
    try {
      await _api.put('/api/bindings/$id', json: body);
      if (!mounted) return;
      setState(() => _binding_saving = false);
      _ui.notify('已绑定');
      _account.clear();
      _password.clear();
      _cookie.clear();
      _appleToken.clear();
      _username.clear();
      _reload();
    } catch (e) {
      if (mounted) setState(() => _binding_saving = false);
      _ui.notify('$e');
    }
  }

  Future<void> _bindAppleToken() async {
    setState(() => _binding_saving = true);
    try {
      await _api.post('/api/bindings/apple/token', json: {
        'mediaUserToken': _appleToken.text.trim(),
        'storefront': 'cn'
      });
      if (!mounted) return;
      setState(() => _binding_saving = false);
      _ui.notify('已绑定');
      _appleToken.clear();
      _reload();
    } catch (e) {
      if (mounted) setState(() => _binding_saving = false);
      _ui.notify('$e');
    }
  }

  Future<void> _unbind() async {
    final ok = await _confirm('解除绑定？', '将删除 ${MX.label(id)} 的登录凭据。');
    if (ok != true) return;
    try {
      await _api.delete('/api/bindings/$id');
      if (!mounted) return;
      _ui.notify('已解除绑定');
      _reload();
    } catch (e) {
      _ui.notify('$e');
    }
  }

  // -- service / ingest / schedule saves -------------------------------------

  Future<void> _serviceTest() async {
    setState(() => _serviceTesting = true);
    try {
      await _api.post('/api/settings/services/$id/test',
          json: {'url': _serviceUrl.text.trim()});
      if (!mounted) return;
      setState(() => _serviceTesting = false);
      _ui.notify('连接正常');
    } catch (e) {
      if (mounted) setState(() => _serviceTesting = false);
      _ui.notify('$e');
    }
  }

  Future<void> _serviceSave() async {
    setState(() => _serviceSaving = true);
    try {
      await _api.put('/api/settings/services/$id',
          json: {'url': _serviceUrl.text.trim()});
      if (!mounted) return;
      setState(() => _serviceSaving = false);
      _ui.notify('已保存');
      _reload();
    } catch (e) {
      if (mounted) setState(() => _serviceSaving = false);
      _ui.notify('$e');
    }
  }

  Future<void> _ingestSave() async {
    setState(() => _ingestSaving = true);
    try {
      await _api.put('/api/settings/ingest', json: {
        'kugouGapMs': int.tryParse(_kugouGap.text.trim()) ?? 0,
        'kugouApiGapMs': int.tryParse(_kugouApiGap.text.trim()) ?? 0,
      });
      if (!mounted) return;
      setState(() => _ingestSaving = false);
      _ui.notify('已保存');
    } catch (e) {
      if (mounted) setState(() => _ingestSaving = false);
      _ui.notify('$e');
    }
  }

  Future<void> _scheduleRun() async {
    setState(() => _schRunning = true);
    try {
      await _api.post('/api/settings/schedules/$id/run');
      if (!mounted) return;
      setState(() => _schRunning = false);
      _ui.notify('已开始执行');
    } catch (e) {
      if (mounted) setState(() => _schRunning = false);
      _ui.notify('$e');
    }
  }

  Future<void> _scheduleSave() async {
    setState(() => _schSaving = true);
    try {
      await _api.put('/api/settings/schedules/$id', json: {
        'enabled': _schEnabled,
        'cron': _schCron.text.trim(),
        'tasks': _schTasks.toList(),
        'ttlSeconds': int.tryParse(_schTtl.text.trim()) ?? 0,
        'chartLimit': int.tryParse(_schChartLimit.text.trim()) ?? 0,
      });
      if (!mounted) return;
      setState(() => _schSaving = false);
      _ui.notify('已保存');
    } catch (e) {
      if (mounted) setState(() => _schSaving = false);
      _ui.notify('$e');
    }
  }

  Future<bool?> _confirm(String title, String message) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: MX.panel,
          title: Text(title, style: TextStyle(color: MX.fg)),
          content: Text(message, style: TextStyle(color: MX.dim)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('取消', style: TextStyle(color: MX.dim))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确定',
                    style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      );

  // __APPEND_PLATFORM_BUILD__
  @override
  Widget build(BuildContext context) {
    final tone = MX.tone(id);
    return _settingsScaffold(
      MX.label(id),
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _headerCard(tone),
          if (_qrActive) ...[
            const SizedBox(height: 16),
            _qrCard(),
          ],
          if (_supportsBinding) ...[
            const SizedBox(height: 16),
            _bindCard(),
          ],
          if (_service != null) ...[
            const SizedBox(height: 16),
            _serviceCard(),
          ],
          if (_supportsIngest && id == 'kugou') ...[
            const SizedBox(height: 16),
            _ingestCard(),
          ],
          const SizedBox(height: 16),
          _scheduleCard(),
        ],
      ),
    );
  }

  Widget _headerCard(Color tone) {
    final bound = _binding?.bound == true;
    return _Card(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: tone.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(MX.icon(id), color: tone, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(MX.label(id),
                    style: TextStyle(
                        color: MX.fg,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(bound ? (_binding?.displayName ?? '已连接') : '未绑定',
                    style:
                        TextStyle(color: bound ? tone : MX.mute, fontSize: 13)),
              ],
            ),
          ),
          if (bound)
            TextButton(
              onPressed: _unbind,
              child:
                  const Text('解除绑定', style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
    );
  }

  Widget _qrCard() => _Card(
        child: Column(
          children: [
            Row(
              children: [
                Text('扫码登录',
                    style: TextStyle(
                        color: MX.fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: _closeQr,
                  icon: Icon(Icons.close, color: MX.mute, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_qrImg != null && _qrImg!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                child: _qrImage(_qrImg!),
              )
            else
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 12),
            Text(_qrMessage ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(color: MX.mute, fontSize: 13)),
          ],
        ),
      );

  Widget _qrImage(String src) {
    final provider = dataUrlImage(src);
    if (provider != null)
      return Image(image: provider, width: 200, height: 200);
    return Image.network(src, width: 200, height: 200);
  }

  Widget _bindCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('绑定账号', Icons.link),
          const SizedBox(height: 12),
          ..._bindEditor(),
        ],
      ),
    );
  }

  List<Widget> _bindEditor() {
    switch (id) {
      case 'netease':
        return [
          _pill('扫码绑定', Icons.qr_code, () => _startQr(), filled: true),
          const SizedBox(height: 14),
          Text('或使用账号密码', style: TextStyle(color: MX.mute, fontSize: 12)),
          const SizedBox(height: 10),
          _field(_account, '账号'),
          const SizedBox(height: 10),
          _field(_password, '密码', obscure: true),
          const SizedBox(height: 14),
          _bindButton(() => _bind(
              {'account': _account.text.trim(), 'password': _password.text})),
        ];
      case 'qqmusic':
        return [
          _chipWrap([
            _pill('QQ 扫码', Icons.qr_code,
                () => _startQr(loginType: QRLoginType.qq),
                filled: true),
            _pill('微信扫码', Icons.qr_code,
                () => _startQr(loginType: QRLoginType.wechat)),
          ]),
          const SizedBox(height: 14),
          Text('或粘贴 Cookie', style: TextStyle(color: MX.mute, fontSize: 12)),
          const SizedBox(height: 10),
          _field(_cookie, 'Cookie'),
          const SizedBox(height: 14),
          _bindButton(() => _bind({'cookie': _cookie.text.trim()})),
        ];
      case 'kugou':
        return [
          _pill('扫码绑定', Icons.qr_code, () => _startQr(), filled: true),
          const SizedBox(height: 14),
          Text('或粘贴 Cookie', style: TextStyle(color: MX.mute, fontSize: 12)),
          const SizedBox(height: 10),
          _field(_cookie, 'Cookie'),
          const SizedBox(height: 14),
          _bindButton(() => _bind({'cookie': _cookie.text.trim()})),
        ];
      case 'apple':
        return [
          _field(_appleToken, 'Media User Token'),
          const SizedBox(height: 14),
          _bindButton(_bindAppleToken),
        ];
      case 'navidrome':
        return [
          _field(_username, '用户名'),
          const SizedBox(height: 10),
          _field(_password, '密码', obscure: true),
          const SizedBox(height: 14),
          _bindButton(() => _bind(
              {'username': _username.text.trim(), 'password': _password.text})),
        ];
      default:
        return [
          Text('该平台暂不支持绑定', style: TextStyle(color: MX.mute, fontSize: 13))
        ];
    }
  }

  Widget _bindButton(VoidCallback onPressed) => Align(
        alignment: Alignment.centerRight,
        child: _pill(_binding_saving ? '保存中…' : '保存', Icons.check,
            _binding_saving ? null : onPressed,
            filled: true),
      );

  Widget _serviceCard() => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('服务地址', Icons.dns),
            const SizedBox(height: 12),
            _field(_serviceUrl, _service?.hint ?? '服务地址',
                keyboardType: TextInputType.url),
            const SizedBox(height: 14),
            _chipWrap([
              _pill(_serviceTesting ? '测试中…' : '测试', Icons.wifi_tethering,
                  _serviceTesting ? null : _serviceTest),
              _pill(_serviceSaving ? '保存中…' : '保存', Icons.check,
                  _serviceSaving ? null : _serviceSave,
                  filled: true),
            ]),
          ],
        ),
      );

  Widget _ingestCard() => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('入库音质', Icons.high_quality),
            const SizedBox(height: 8),
            Text('最高可用完整音质，酷狗可调节请求间隔以规避风控。',
                style: TextStyle(color: MX.mute, fontSize: 12)),
            const SizedBox(height: 12),
            _numberField(_kugouGap, '任务间隔（毫秒）'),
            const SizedBox(height: 10),
            _numberField(_kugouApiGap, 'API 间隔（毫秒）'),
            if (_kugouRangeCaption != null) ...[
              const SizedBox(height: 10),
              Text(_kugouRangeCaption!,
                  style: TextStyle(color: MX.mute, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: _pill(_ingestSaving ? '保存中…' : '保存', Icons.check,
                  _ingestSaving ? null : _ingestSave,
                  filled: true),
            ),
          ],
        ),
      );

  Widget _scheduleCard() => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('定时缓存', Icons.schedule),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: Text('启用',
                        style: TextStyle(color: MX.fg, fontSize: 15))),
                Switch(
                    value: _schEnabled,
                    activeColor: MX.ember,
                    onChanged: (v) => setState(() => _schEnabled = v)),
              ],
            ),
            const SizedBox(height: 10),
            _field(_schCron, 'Cron 表达式'),
            const SizedBox(height: 12),
            Text('预热任务',
                style: TextStyle(
                    color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _chipWrap([
              for (final t in _taskCatalog)
                _MXChip(
                  label: t.$2,
                  selected: _schTasks.contains(t.$1),
                  onTap: () => setState(() => _schTasks.contains(t.$1)
                      ? _schTasks.remove(t.$1)
                      : _schTasks.add(t.$1)),
                ),
            ]),
            const SizedBox(height: 12),
            _numberField(_schTtl, '缓存 TTL（秒）'),
            const SizedBox(height: 10),
            _numberField(_schChartLimit, '预热榜单数量'),
            const SizedBox(height: 14),
            _chipWrap([
              _pill(_schRunning ? '执行中…' : '立即执行', Icons.play_arrow,
                  _schRunning ? null : _scheduleRun),
              _pill(_schSaving ? '保存中…' : '保存', Icons.check,
                  _schSaving ? null : _scheduleSave,
                  filled: true),
            ]),
          ],
        ),
      );
}

// ===========================================================================
// CustomSourcesView — LX custom source scripts.
// ===========================================================================

class CustomSourcesView extends StatefulWidget {
  const CustomSourcesView({super.key});
  @override
  State<CustomSourcesView> createState() => _CustomSourcesViewState();
}

class _CustomSourcesViewState extends State<CustomSourcesView> {
  List<LxSourceSummary> _sources = [];
  final _filename = TextEditingController(text: 'lx-custom-source.js');
  final _content = TextEditingController();
  bool _validating = false, _saving = false;
  String? _validateCaption;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _filename.dispose();
    _content.dispose();
    super.dispose();
  }

  UIStore get _ui => context.read<UIStore>();
  APIClient get _api => context.read<SessionStore>().api;
  bool get _isAdmin => context.read<SessionStore>().role == 'admin';

  Future<void> _reload() async {
    try {
      final box =
          await _api.getJson('/api/settings/lx-sources', LxSourcesBox.fromJson);
      _sources = box.sources ?? [];
    } catch (_) {}
    if (mounted) setState(() {});
  }

  int get _readyCount => _sources
      .where((s) => (s.status ?? '') == 'ready' && (s.enabled ?? false))
      .length;

  Color _sourceTone(LxSourceSummary s) {
    if (s.enabled != true) return MX.dimSoft;
    if ((s.status ?? '') == 'ready') return const Color(0xFF34C759);
    return Colors.redAccent;
  }

  String _statusLabel(LxSourceSummary s) {
    if (s.enabled != true) return '已停用';
    return (s.status ?? '') == 'ready' ? '可用' : '异常';
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['js'],
        withData: true,
      );
      final file =
          (res != null && res.files.isNotEmpty) ? res.files.first : null;
      if (file == null) return;
      String? text;
      if (file.bytes != null) {
        text = utf8.decode(file.bytes!, allowMalformed: true);
      }
      if (text != null && mounted) {
        setState(() {
          _content.text = text!;
          if (file.name.isNotEmpty) _filename.text = file.name;
        });
      }
    } catch (e) {
      _ui.notify('$e');
    }
  }

  Future<void> _validate() async {
    setState(() => _validating = true);
    try {
      final res = await _api.postJson(
          '/api/settings/lx-sources/validate', LxSourceValidation.fromJson,
          json: {'content': _content.text});
      if (!mounted) return;
      setState(() {
        _validating = false;
        if (res.valid == true) {
          final srcs = (res.supportedSources ?? []).map(MX.label).join('、');
          _validateCaption = '校验通过${srcs.isEmpty ? '' : ' · 支持 $srcs'}';
        } else {
          _validateCaption = '校验未通过';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _validating = false);
      _ui.notify('$e');
    }
  }

  Future<void> _saveSource() async {
    setState(() => _saving = true);
    try {
      await _api
          .postJson('/api/settings/lx-sources', LxSourcesBox.fromJson, json: {
        'filename': _filename.text.trim(),
        'content': _content.text,
        'enabled': true,
      });
      if (!mounted) return;
      setState(() {
        _saving = false;
        _content.clear();
        _validateCaption = null;
      });
      _ui.notify('已保存');
      _reload();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _ui.notify('$e');
    }
  }

  Future<void> _toggle(LxSourceSummary s) async {
    try {
      await _api.put('/api/settings/lx-sources/${Uri.encodeComponent(s.id)}',
          json: {'enabled': !(s.enabled ?? false)});
      _reload();
    } catch (e) {
      _ui.notify('$e');
    }
  }

  Future<void> _remove(LxSourceSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('删除这个自定义音源？', style: TextStyle(color: MX.fg)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消', style: TextStyle(color: MX.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('删除', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api
          .delete('/api/settings/lx-sources/${Uri.encodeComponent(s.id)}');
      _ui.notify('已删除');
      _reload();
    } catch (e) {
      _ui.notify('$e');
    }
  }

  Future<void> _export(LxSourceSummary s) async {
    try {
      final data = await _api.getData(
          '/api/settings/lx-sources/${Uri.encodeComponent(s.id)}/export');
      final content = (data is Map ? data['content']?.toString() : null) ?? '';
      await Clipboard.setData(ClipboardData(text: content));
      _ui.notify('脚本已复制到剪贴板');
    } catch (e) {
      _ui.notify('$e');
    }
  }

  // __APPEND_CUSTOMSOURCES_BUILD__
  @override
  Widget build(BuildContext context) {
    final tone = MX.tone('lx');
    return _settingsScaffold(
      'LX 自定义音源',
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Card(
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: tone.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.graphic_eq, color: tone, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('自定义音源',
                          style: TextStyle(
                              color: MX.fg,
                              fontSize: 17,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${_sources.length} 个脚本 · $_readyCount 个可用',
                          style: TextStyle(color: MX.mute, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(_isAdmin ? '可添加、启用与导出 LX 音源脚本。' : '仅管理员可管理自定义音源。',
                          style: TextStyle(color: MX.mute, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionTitle('已添加音源'),
          const SizedBox(height: 8),
          if (_sources.isEmpty)
            _Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('尚未添加自定义音源',
                      style: TextStyle(color: MX.mute, fontSize: 13)),
                ),
              ),
            )
          else
            _Card(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (int i = 0; i < _sources.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: MX.line),
                    _sourceRow(_sources[i]),
                  ],
                ],
              ),
            ),
          if (_isAdmin) ...[
            const SizedBox(height: 20),
            _editorCard(),
          ],
        ],
      ),
    );
  }

  Widget _sourceRow(LxSourceSummary s) {
    final tone = _sourceTone(s);
    final detail = <String>[];
    if (s.author != null && s.author!.isNotEmpty) detail.add(s.author!);
    if (s.version != null && s.version!.isNotEmpty) detail.add(s.version!);
    if (s.supportedSources != null && s.supportedSources!.isNotEmpty) {
      detail.add('支持 ${s.supportedSources!.map(MX.label).join('、')}');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: tone.withOpacity(0.14),
                borderRadius: BorderRadius.circular(7)),
            child: Icon(Icons.graphic_eq, size: 16, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(s.name ?? s.filename ?? s.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MX.fg, fontSize: 15)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: tone.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(_statusLabel(s),
                          style: TextStyle(color: tone, fontSize: 11)),
                    ),
                  ],
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(detail.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MX.mute, fontSize: 12)),
                ],
                if (s.error != null && s.error!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(s.error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12)),
                ],
              ],
            ),
          ),
          if (_isAdmin)
            PopupMenuButton<String>(
              color: MX.panel,
              icon: Icon(Icons.more_horiz, color: MX.mute, size: 20),
              onSelected: (v) {
                switch (v) {
                  case 'toggle':
                    _toggle(s);
                    break;
                  case 'export':
                    _export(s);
                    break;
                  case 'delete':
                    _remove(s);
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'toggle',
                    child: Text((s.enabled ?? false) ? '停用' : '启用',
                        style: TextStyle(color: MX.fg))),
                PopupMenuItem(
                    value: 'export',
                    child: Text('导出脚本', style: TextStyle(color: MX.fg))),
                const PopupMenuItem(
                    value: 'delete',
                    child:
                        Text('删除', style: TextStyle(color: Colors.redAccent))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _editorCard() => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('添加音源', Icons.add_circle_outline),
            const SizedBox(height: 12),
            _field(_filename, '文件名，如 lx-custom-source.js'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: MX.fillStrong,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MX.hairline),
              ),
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _content,
                maxLines: null,
                minLines: 8,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12, color: Colors.white),
                decoration: InputDecoration.collapsed(
                  hintText: '粘贴 LX 音源脚本，或从 JS 文件导入…',
                  hintStyle: TextStyle(color: MX.mute),
                ),
              ),
            ),
            if (_validateCaption != null) ...[
              const SizedBox(height: 10),
              Text(_validateCaption!,
                  style: TextStyle(color: MX.mute, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            _chipWrap([
              _pill('从文件读取', Icons.upload_file, _pickFile),
              _pill(_validating ? '校验中…' : '校验', Icons.fact_check,
                  _validating ? null : _validate),
              _pill(_saving ? '保存中…' : '保存', Icons.check,
                  _saving ? null : _saveSource,
                  filled: true),
            ]),
          ],
        ),
      );
}
