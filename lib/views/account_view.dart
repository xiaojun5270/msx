import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';

/// The profile tab. Mirrors Swift `AccountView`: an account hero, custom
/// playlists, library shortcuts, management shortcuts, and platform playlists.
class AccountView extends StatefulWidget {
  const AccountView({super.key});

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  List<Playlist> _playlists = [];
  List<(String, List<Playlist>)> _platformGroups = [];
  int _subscriptionCount = 0;

  static const _weights = {
    'apple': 4,
    'navidrome': 2,
    'netease': 1,
    'qqmusic': 1,
    'kugou': 1
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    final cachedLib =
        session.peekPage('profile.libraries', LibraryPayload.fromJson);
    if (cachedLib != null) _applyLibraries(cachedLib);
    final cachedPl =
        session.peekPage('profile.playlists', PlaylistsPayload.fromJson);
    if (cachedPl != null) {
      _playlists = (cachedPl.playlists ?? [])
          .where((p) => p.kind != 'favorites' && p.listKind != 'favorites')
          .toList();
    }
    if (mounted) setState(() {});

    await session.refreshBindings();
    try {
      final me = await session.api.getJson('/api/me', Me.fromJson);
      await session.apply(me);
    } catch (_) {}

    final lib = await session.fetchPage('/api/me/libraries/playlists',
        cacheKey: 'profile.libraries', factory: LibraryPayload.fromJson);
    if (lib != null) _applyLibraries(lib);
    final box = await session.fetchPage('/api/my/playlists',
        cacheKey: 'profile.playlists', factory: PlaylistsPayload.fromJson);
    if (box != null) {
      _playlists = (box.playlists ?? [])
          .where((p) => p.kind != 'favorites' && p.listKind != 'favorites')
          .toList();
    }
    try {
      final subs = await session.api
          .getJson('/api/subscriptions', SubscriptionsBox.fromJson);
      _subscriptionCount = subs.items?.length ?? 0;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _applyLibraries(LibraryPayload lib) {
    final groups = lib.groups ?? {};
    final out = <(String, List<Playlist>)>[];
    for (final id in MX.platforms) {
      final list = (groups[id] ?? []).where((p) => p.id != 'liked').toList();
      if (list.isNotEmpty) out.add((id, list));
    }
    out.sort((a, b) => (_weights[b.$1] ?? 0).compareTo(_weights[a.$1] ?? 0));
    _platformGroups = out;
  }

  int get _boundCount => context
      .read<SessionStore>()
      .bindings
      .values
      .where((b) => b.bound == true)
      .length;

  AppRoute _playlistRoute(Playlist p) {
    final platform = p.platform ?? 'local';
    final kind = platform == 'local' || p.listKind == 'mine'
        ? ListKind.mine
        : (p.listKind == 'chart' ? ListKind.chart : ListKind.platform);
    return PlaylistRoute(
        platform: platform, id: p.id, kind: kind, fromLibrary: true);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final ui = context.read<UIStore>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text('我的',
            style: TextStyle(
                color: MX.fg, fontWeight: FontWeight.bold, fontSize: 26)),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: MX.fg),
            tooltip: '设置',
            onPressed: () => ui.open(const SimpleRoute('settings')),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: MX.ember,
        backgroundColor: MX.panel,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.paddingOf(context).bottom),
          children: [
            _hero(session),
            const SizedBox(height: 24),
            _customPlaylists(ui),
            const SizedBox(height: 24),
            _librarySection(ui),
            const SizedBox(height: 24),
            _managementSection(ui),
            const SizedBox(height: 24),
            _platformPlaylists(ui),
          ],
        ),
      ),
    );
  }

  Widget _hero(SessionStore session) {
    final subtitle =
        '${session.role == 'admin' ? '管理员' : '普通账号'} · $_boundCount 个平台已连接';
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: MX.hairline),
          ),
          child: CoverArt(src: session.avatarUrl, size: 96, circle: true),
        ),
        const SizedBox(height: 14),
        Text(session.nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: MX.fg, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: MX.mute, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: MX.ember.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq, size: 13, color: MX.ember),
              const SizedBox(width: 5),
              Text(session.role == 'admin' ? '管理员空间' : '个人音乐空间',
                  style: TextStyle(
                      color: MX.ember,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _metric('${_playlists.length}', '我的歌单'),
            _metric('$_boundCount', '已连接'),
            _metric('$_subscriptionCount', '订阅任务'),
          ],
        ),
      ],
    );
  }

  Widget _metric(String value, String title) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: MX.fg, fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(title, style: TextStyle(color: MX.mute, fontSize: 12)),
          ],
        ),
      );

  Widget _sectionHeader(String title, String? detail) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(title,
                style: TextStyle(
                    color: MX.fg, fontSize: 20, fontWeight: FontWeight.bold)),
            if (detail != null) ...[
              const SizedBox(width: 8),
              Text(detail, style: TextStyle(color: MX.mute, fontSize: 13)),
            ],
          ],
        ),
      );

  Widget _customPlaylists(UIStore ui) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
            '我的歌单', _playlists.isEmpty ? null : '${_playlists.length} 个'),
        if (_playlists.isEmpty)
          _emptyRow(
              Icons.queue_music, '还没有歌单', '新建歌单后，可选用 MusicX 服务器可访问的 NAS 音乐目录。')
        else
          _glassPanel(
            child: Column(
              children: [
                for (var i = 0; i < _playlists.length; i++) ...[
                  _playlistRow(
                      ui,
                      _playlists[i],
                      _playlists[i].ingestEnabled == true ? '自动入库' : '手动入库',
                      _playlists[i].ingestEnabled == true ? MX.ember : MX.mute),
                  if (i < _playlists.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 80),
                      child: Divider(color: MX.hairline, height: 1),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _playlistRow(
      UIStore ui, Playlist p, String sourceLabel, Color sourceTint) {
    return InkWell(
      onTap: () => ui.open(_playlistRoute(p)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CoverArt(src: p.cover, mosaic: p.artTiles, size: 52, corner: 8),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: MX.fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(sourceLabel,
                      style: TextStyle(color: sourceTint, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: MX.dimSoft, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _librarySection(UIStore ui) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('资料库', '随时继续聆听'),
        _actionCard(Icons.favorite, '喜欢的音乐', '歌曲、专辑与歌单',
            () => ui.open(const SimpleRoute('favorites'))),
        const SizedBox(height: 10),
        _actionCard(
            Icons.notifications,
            '订阅任务',
            _subscriptionCount > 0
                ? '$_subscriptionCount 个自动刷新任务'
                : '自动刷新歌单与榜单',
            () => ui.open(const SimpleRoute('subscriptions'))),
        const SizedBox(height: 10),
        _actionCard(Icons.folder, '本地文件', '设备上的离线音乐',
            () => ui.open(const SimpleRoute('files'))),
      ],
    );
  }

  Widget _managementSection(UIStore ui) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('管理', '同步与入库'),
        _actionCard(Icons.graphic_eq, '音源整理记录', '整理与后台入库进度',
            () => ui.open(const SimpleRoute('source-runs'))),
        const SizedBox(height: 10),
        _actionCard(Icons.inbox, '入库记录', '下载、入库与失败原因',
            () => ui.open(const SimpleRoute('ingest-records'))),
      ],
    );
  }

  Widget _platformPlaylists(UIStore ui) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('平台歌单', _platformGroups.isEmpty ? null : '已同步'),
        if (_platformGroups.isEmpty)
          _emptyRow(Icons.queue_music, '暂无平台歌单', '连接音乐平台后，这里会展示你的歌单。')
        else
          for (final group in _platformGroups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 10),
              child: Row(
                children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: MX.tone(group.$1), shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text(MX.label(group.$1),
                      style: TextStyle(
                          color: MX.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Text('${group.$2.length} 个',
                      style: TextStyle(color: MX.mute, fontSize: 12)),
                ],
              ),
            ),
            _glassPanel(
              child: Column(
                children: [
                  for (var i = 0; i < group.$2.length; i++) ...[
                    _playlistRow(
                        ui, group.$2[i], MX.label(group.$1), MX.tone(group.$1)),
                    if (i < group.$2.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 80),
                        child: Divider(color: MX.hairline, height: 1),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }

  Widget _actionCard(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: _glassPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: MX.ember.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: MX.ember, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: MX.fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(color: MX.mute, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: MX.dimSoft, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _emptyRow(IconData icon, String title, String subtitle) => _glassPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: MX.dim, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: MX.fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(color: MX.mute, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _glassPanel({
    required Widget child,
    EdgeInsets padding = EdgeInsets.zero,
  }) =>
      Padding(
        padding: padding,
        child: SizedBox(width: double.infinity, child: child),
      );
}
