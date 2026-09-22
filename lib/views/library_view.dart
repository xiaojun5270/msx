import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';

// ---------------------------------------------------------------------------
// LibraryView — category list + recently added grid. Mirrors Swift `LibraryView`.
// ---------------------------------------------------------------------------

enum _RecentRemoveKind { none, album, favoritePlaylist, minePlaylist }

class _RecentTile {
  final String id;
  final String title;
  final String subtitle;
  final String? cover;
  final List<String>? mosaic;
  final String? platform;
  final AppRoute route;
  final DateTime date;
  final _RecentRemoveKind removeKind;
  final Album? album;
  final Playlist? playlist;

  _RecentTile({
    required this.id,
    required this.title,
    required this.subtitle,
    this.cover,
    this.mosaic,
    this.platform,
    required this.route,
    required this.date,
    required this.removeKind,
    this.album,
    this.playlist,
  });

  bool get canRemove => removeKind != _RecentRemoveKind.none;

  static _RecentTile fromAlbum(Album a) => _RecentTile(
        id: 'album:${a.platform}::${a.id}',
        title: a.displayTitle,
        subtitle: a.artistText,
        cover: a.cover,
        platform: a.platform,
        route: AlbumRoute(platform: a.platform, id: a.id),
        date: _parse(a.addedAt),
        removeKind: _RecentRemoveKind.album,
        album: a,
      );

  static _RecentTile fromPlaylist(Playlist p, _RecentRemoveKind removeKind) => _RecentTile(
        id: 'playlist:${p.platform ?? 'local'}::${p.id}',
        title: p.displayTitle,
        subtitle: p.kind == 'favorites'
            ? '收藏的歌曲'
            : (p.platform == null || p.platform == 'local' || p.kind == 'custom' ? '播放列表' : '歌单'),
        cover: p.cover,
        mosaic: p.artTiles,
        platform: p.platform,
        route: _playlistRoute(p, fromLibrary: true),
        date: _parse(p.addedAt ?? p.updatedAt ?? p.createdAt),
        removeKind: removeKind,
        playlist: p,
      );

  static DateTime _parse(String? raw) {
    if (raw == null || raw.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(raw)?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}

AppRoute _playlistRoute(Playlist p, {required bool fromLibrary}) {
  final plat = p.platform ?? 'local';
  if (plat == 'local' || p.listKind == 'mine' || p.kind == 'favorites') {
    return PlaylistRoute(platform: plat, id: p.id, kind: ListKind.mine, fromLibrary: fromLibrary);
  }
  if (p.listKind == 'chart') {
    return PlaylistRoute(platform: plat, id: p.id, kind: ListKind.chart, fromLibrary: fromLibrary);
  }
  return PlaylistRoute(platform: plat, id: p.id, kind: ListKind.platform, fromLibrary: fromLibrary);
}

class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  List<_RecentTile> _recent = [];
  bool _loading = true;

  static const _categories = <(IconData, String, LibrarySection?)>[
    (Icons.queue_music, '播放列表', LibrarySection.playlists),
    (Icons.mic_none, '艺人', LibrarySection.artists),
    (Icons.album, '专辑', LibrarySection.albums),
    (Icons.music_note, '歌曲', LibrarySection.songs),
    (Icons.folder, '文件', null),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    var albums = session.peekPage('library.recent.albums', (m) => ItemsBox.fromJson(m, Album.fromJson))?.items ?? [];
    var lists = session.peekPage('library.recent.playlists', (m) => ItemsBox.fromJson(m, Playlist.fromJson))?.items ?? [];
    var mine = session.peekPage('library.recent.mine', PlaylistsPayload.fromJson)?.playlists ?? [];
    if (_recent.isEmpty) _apply(albums, lists, mine);

    final albumsBox = await session.fetchPage('/api/my/favorites/items?kind=album',
        cacheKey: 'library.recent.albums', factory: (m) => ItemsBox.fromJson(m, Album.fromJson));
    final listsBox = await session.fetchPage('/api/my/favorites/items?kind=playlist',
        cacheKey: 'library.recent.playlists', factory: (m) => ItemsBox.fromJson(m, Playlist.fromJson));
    final mineBox = await session.fetchPage('/api/my/playlists',
        cacheKey: 'library.recent.mine', factory: PlaylistsPayload.fromJson);
    if (albumsBox != null) albums = albumsBox.items ?? [];
    if (listsBox != null) lists = listsBox.items ?? [];
    if (mineBox != null) mine = mineBox.playlists ?? [];
    if (mounted) _apply(albums, lists, mine);
  }

  void _apply(List<Album> albums, List<Playlist> lists, List<Playlist> mine) {
    final tiles = <_RecentTile>[
      ...albums.map(_RecentTile.fromAlbum),
      ...lists.map((p) => _RecentTile.fromPlaylist(p, _RecentRemoveKind.favoritePlaylist)),
      ...mine.map((p) =>
          _RecentTile.fromPlaylist(p, p.kind == 'favorites' ? _RecentRemoveKind.none : _RecentRemoveKind.minePlaylist)),
    ];
    final seen = <String>{};
    final deduped = tiles.where((t) => seen.add(t.id)).toList()..sort((a, b) => b.date.compareTo(a.date));
    setState(() {
      _recent = deduped.take(12).toList();
      _loading = false;
    });
  }

  Future<void> _remove(_RecentTile item) async {
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      switch (item.removeKind) {
        case _RecentRemoveKind.none:
          return;
        case _RecentRemoveKind.album:
          final a = item.album!;
          final body = <String, dynamic>{'kind': 'album', 'id': a.id, 'platform': a.platform, 'title': a.displayTitle};
          if (a.cover != null) body['artworkUrl'] = a.cover;
          await session.api.post('/api/my/favorites/items/toggle', json: body);
          break;
        case _RecentRemoveKind.favoritePlaylist:
          final p = item.playlist!;
          final body = <String, dynamic>{'kind': 'playlist', 'id': p.id, 'platform': p.platform ?? 'local', 'title': p.displayTitle};
          if (p.cover != null) {
            body['coverUrl'] = p.cover;
            body['artworkUrl'] = p.cover;
          }
          await session.api.post('/api/my/favorites/items/toggle', json: body);
          break;
        case _RecentRemoveKind.minePlaylist:
          await session.api.delete('/api/my/playlists/${item.playlist!.id}');
          break;
      }
      ui.notify('已从资料库删除');
      await _load();
    } catch (e) {
      ui.notify('$e');
    }
  }

  void _confirmRemove(_RecentTile item) {
    final mine = item.removeKind == _RecentRemoveKind.minePlaylist;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('从资料库删除「${item.title}」？', style: TextStyle(color: MX.fg, fontSize: 17)),
        content: Text(mine ? '将删除此播放列表。' : '将从资料库移除，不会删除平台上的内容。',
            style: TextStyle(color: MX.dim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _remove(item);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MX.ink,
      appBar: AppBar(
        backgroundColor: MX.ink,
        surfaceTintColor: Colors.transparent,
        title: Text('资料库', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold, fontSize: 26)),
      ),
      body: RefreshIndicator(
        color: MX.ember,
        backgroundColor: MX.panel,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: [
            _categoryList(),
            const SizedBox(height: 32),
            _recentSection(),
          ],
        ),
      ),
    );
  }

  Widget _categoryList() {
    final ui = context.read<UIStore>();
    return Column(
      children: [
        for (var i = 0; i < _categories.length; i++) ...[
          InkWell(
            onTap: () => ui.open(_categories[i].$3 == null
                ? const SimpleRoute('files')
                : LibrarySectionRoute(_categories[i].$3!)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 44,
                    child: Icon(_categories[i].$1, color: MX.ember, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Text(_categories[i].$2, style: TextStyle(color: MX.fg, fontSize: 20)),
                  const Spacer(),
                ],
              ),
            ),
          ),
          if (i < _categories.length - 1)
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Divider(color: MX.line, height: 1),
            ),
        ],
      ],
    );
  }

  Widget _recentSection() {
    if (_loading && _recent.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('最近添加', style: TextStyle(color: MX.fg, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.78,
            crossAxisSpacing: 16,
            mainAxisSpacing: 18,
            children: [for (var i = 0; i < 4; i++) const _CoverCardSkeleton()],
          ),
        ],
      );
    }
    if (_recent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近添加', style: TextStyle(color: MX.fg, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.78,
          crossAxisSpacing: 16,
          mainAxisSpacing: 18,
          children: [
            for (final item in _recent)
              GestureDetector(
                onLongPress: item.canRemove ? () => _confirmRemove(item) : null,
                child: CatalogTile(
                  cover: item.cover,
                  mosaic: item.mosaic,
                  title: item.title,
                  subtitle: item.subtitle,
                  platform: item.platform,
                  route: item.route,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// LibraryBrowseView — per-section browser. Mirrors Swift `LibraryBrowseView`.
// ---------------------------------------------------------------------------

enum _BrowseOrigin { mine, platformLibrary, favorite }

class _BrowsePlaylist {
  final String id;
  final Playlist playlist;
  final String platform;
  final ListKind kind;
  final bool pinned;
  final _BrowseOrigin origin;
  _BrowsePlaylist(this.id, this.playlist, this.platform, this.kind, this.pinned, this.origin);
  bool get canRemove => !pinned && origin != _BrowseOrigin.platformLibrary;
}

class LibraryBrowseView extends StatefulWidget {
  final LibrarySection section;
  const LibraryBrowseView({super.key, required this.section});

  @override
  State<LibraryBrowseView> createState() => _LibraryBrowseViewState();
}

class _LibraryBrowseViewState extends State<LibraryBrowseView> {
  List<_BrowsePlaylist> _items = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  List<Track> _tracks = [];
  bool _loading = true;

  LibrarySection get section => widget.section;

  String get _title {
    switch (section) {
      case LibrarySection.playlists:
        return '播放列表';
      case LibrarySection.artists:
        return '艺人';
      case LibrarySection.albums:
        return '专辑';
      case LibrarySection.songs:
        return '歌曲';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    switch (section) {
      case LibrarySection.playlists:
        await _loadPlaylists(session);
        break;
      case LibrarySection.albums:
        final cached = session.peekPage('library.browse.albums', (m) => ItemsBox.fromJson(m, Album.fromJson));
        if (_albums.isEmpty && cached != null) _albums = cached.items ?? [];
        final box = await session.fetchPage('/api/my/favorites/items?kind=album',
            cacheKey: 'library.browse.albums', factory: (m) => ItemsBox.fromJson(m, Album.fromJson));
        if (box != null) _albums = box.items ?? [];
        break;
      case LibrarySection.artists:
        final cached = session.peekPage('library.browse.artists', (m) => ItemsBox.fromJson(m, Artist.fromJson));
        if (_artists.isEmpty && cached != null) _artists = cached.items ?? [];
        final box = await session.fetchPage('/api/my/favorites/items?kind=artist',
            cacheKey: 'library.browse.artists', factory: (m) => ItemsBox.fromJson(m, Artist.fromJson));
        if (box != null) _artists = box.items ?? [];
        break;
      case LibrarySection.songs:
        await _loadSongs(session);
        break;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSongs(SessionStore session) async {
    final cached = session.peekPage('library.browse.songs', PlaylistBox.fromJson);
    if (_tracks.isEmpty && cached != null) _tracks = cached.playlist?.tracks ?? [];
    var mine = session.peekPage('library.recent.mine', PlaylistsPayload.fromJson);
    final box = await session.fetchPage('/api/my/playlists', cacheKey: 'library.recent.mine', factory: PlaylistsPayload.fromJson);
    if (box != null) mine = box;
    String? favId;
    for (final p in mine?.playlists ?? []) {
      if (p.kind == 'favorites') {
        favId = p.id;
        break;
      }
    }
    if (favId == null) return;
    final row = await session.fetchPage('/api/my/playlists/$favId', cacheKey: 'library.browse.songs', factory: PlaylistBox.fromJson);
    if (row != null) _tracks = row.playlist?.tracks ?? [];
  }

  Future<void> _loadPlaylists(SessionStore session) async {
    var mine = session.peekPage('library.recent.mine', PlaylistsPayload.fromJson);
    var lib = session.peekPage('library.browse.lib', LibraryPayload.fromJson);
    var fav = session.peekPage('library.browse.favPlaylists', (m) => ItemsBox.fromJson(m, Playlist.fromJson));
    if (_items.isEmpty) {
      _applyPlaylists(mine?.playlists ?? [], lib?.groups ?? {}, fav?.items ?? []);
    }
    final mineBox = await session.fetchPage('/api/my/playlists', cacheKey: 'library.recent.mine', factory: PlaylistsPayload.fromJson);
    final libBox = await session.fetchPage('/api/me/libraries/playlists', cacheKey: 'library.browse.lib', factory: LibraryPayload.fromJson);
    final favBox = await session.fetchPage('/api/my/favorites/items?kind=playlist',
        cacheKey: 'library.browse.favPlaylists', factory: (m) => ItemsBox.fromJson(m, Playlist.fromJson));
    if (mineBox != null) mine = mineBox;
    if (libBox != null) lib = libBox;
    if (favBox != null) fav = favBox;
    _applyPlaylists(mine?.playlists ?? [], lib?.groups ?? {}, fav?.items ?? []);
  }

  void _applyPlaylists(List<Playlist> mine, Map<String, List<Playlist>> groups, List<Playlist> favs) {
    final seen = <String>{};
    final out = <_BrowsePlaylist>[];
    Playlist? favorites;
    for (final p in mine) {
      if (p.kind == 'favorites') {
        favorites = p;
        break;
      }
    }
    if (favorites != null) {
      final key = 'local::${favorites.id}';
      seen.add(key);
      out.add(_BrowsePlaylist(key, favorites, 'local', ListKind.mine, true, _BrowseOrigin.mine));
    }
    final rest = <_BrowsePlaylist>[];
    for (final p in mine) {
      if (p.kind == 'favorites') continue;
      final key = 'local::${p.id}';
      if (seen.add(key)) {
        rest.add(_BrowsePlaylist(key, p, 'local', ListKind.mine, false, _BrowseOrigin.mine));
      }
    }
    groups.forEach((platform, list) {
      for (final p in list) {
        if (p.id == 'liked') continue;
        final plat = p.platform ?? platform;
        final key = '$plat::${p.id}';
        if (seen.add(key)) {
          rest.add(_BrowsePlaylist(key, p, plat, ListKind.platform, false, _BrowseOrigin.platformLibrary));
        }
      }
    });
    for (final p in favs) {
      final plat = p.platform ?? 'local';
      final key = '$plat::${p.id}';
      if (seen.add(key)) {
        final kind = plat == 'local' || p.listKind == 'mine'
            ? ListKind.mine
            : (p.listKind == 'chart' ? ListKind.chart : ListKind.platform);
        rest.add(_BrowsePlaylist(key, p, plat, kind, false, _BrowseOrigin.favorite));
      }
    }
    rest.sort((a, b) => a.playlist.displayTitle.toLowerCase().compareTo(b.playlist.displayTitle.toLowerCase()));
    setState(() => _items = [...out, ...rest]);
  }

  Future<void> _createPlaylist(String name) async {
    final title = name.trim();
    if (title.isEmpty) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      await session.api.post('/api/my/playlists', json: {'name': title});
      ui.notify('已创建');
      await _loadPlaylists(session);
    } catch (e) {
      ui.notify('$e');
    }
  }

  void _promptCreate() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('新建歌单', style: TextStyle(color: MX.fg)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: MX.fg),
          decoration: InputDecoration(hintText: '名称', hintStyle: TextStyle(color: MX.dim)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _createPlaylist(ctrl.text);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeAlbum(Album a) async {
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    final body = <String, dynamic>{'kind': 'album', 'id': a.id, 'platform': a.platform, 'title': a.displayTitle};
    if (a.cover != null) body['artworkUrl'] = a.cover;
    try {
      await session.api.post('/api/my/favorites/items/toggle', json: body);
      ui.notify('已从资料库删除');
      await _load();
    } catch (e) {
      ui.notify('$e');
    }
  }

  Future<void> _removeArtist(Artist a) async {
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    final body = <String, dynamic>{'kind': 'artist', 'id': a.id, 'platform': a.platform, 'name': a.displayName};
    if (a.cover != null) body['avatarUrl'] = a.cover;
    try {
      await session.api.post('/api/my/favorites/items/toggle', json: body);
      ui.notify('已从资料库删除');
      await _load();
    } catch (e) {
      ui.notify('$e');
    }
  }

  Future<void> _removePlaylist(_BrowsePlaylist row) async {
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      switch (row.origin) {
        case _BrowseOrigin.mine:
          await session.api.delete('/api/my/playlists/${row.playlist.id}');
          break;
        case _BrowseOrigin.favorite:
          final body = <String, dynamic>{
            'kind': 'playlist',
            'id': row.playlist.id,
            'platform': row.platform,
            'title': row.playlist.displayTitle
          };
          if (row.playlist.cover != null) {
            body['coverUrl'] = row.playlist.cover;
            body['artworkUrl'] = row.playlist.cover;
          }
          await session.api.post('/api/my/favorites/items/toggle', json: body);
          break;
        case _BrowseOrigin.platformLibrary:
          return;
      }
      ui.notify('已从资料库删除');
      await _load();
    } catch (e) {
      ui.notify('$e');
    }
  }

  void _confirmRemove(String title, bool isMine, VoidCallback action) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('从资料库删除「$title」？', style: TextStyle(color: MX.fg, fontSize: 17)),
        content: Text(isMine ? '将删除此播放列表。' : '将从资料库移除，不会删除平台上的内容。', style: TextStyle(color: MX.dim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              action();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  bool get _showLoading {
    switch (section) {
      case LibrarySection.playlists:
        return _loading && _items.isEmpty;
      case LibrarySection.albums:
        return _loading && _albums.isEmpty;
      case LibrarySection.artists:
        return _loading && _artists.isEmpty;
      case LibrarySection.songs:
        return _loading && _tracks.isEmpty;
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    return Scaffold(
      backgroundColor: MX.ink,
      appBar: AppBar(
        backgroundColor: MX.ink,
        surfaceTintColor: Colors.transparent,
        title: Text(_title, style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
        actions: [
          if (section == LibrarySection.playlists)
            IconButton(icon: Icon(Icons.add, color: MX.fg), onPressed: _promptCreate)
          else if (section == LibrarySection.songs && _tracks.isNotEmpty)
            IconButton(icon: Icon(Icons.play_arrow, color: MX.fg), onPressed: () => player.replaceQueue(_tracks, start: 0)),
        ],
      ),
      body: _showLoading
          ? Center(child: CircularProgressIndicator(color: MX.ember))
          : RefreshIndicator(
              color: MX.ember,
              backgroundColor: MX.panel,
              onRefresh: _load,
              child: _content(),
            ),
    );
  }

  Widget _content() {
    switch (section) {
      case LibrarySection.playlists:
        return _playlistGrid();
      case LibrarySection.albums:
        return _albumGrid();
      case LibrarySection.artists:
        return _artistList();
      case LibrarySection.songs:
        return _songList();
    }
  }

  Widget _empty(IconData icon, String title, [String? desc]) => ListView(
        children: [
          const SizedBox(height: 80),
          Icon(icon, color: MX.dim, size: 48),
          const SizedBox(height: 12),
          Center(child: Text(title, style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600))),
          if (desc != null) ...[
            const SizedBox(height: 4),
            Center(child: Text(desc, style: TextStyle(color: MX.dim, fontSize: 13))),
          ],
        ],
      );

  Widget _playlistGrid() {
    if (_items.isEmpty) return _empty(Icons.queue_music, '暂无播放列表');
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 0.72,
      crossAxisSpacing: 14,
      mainAxisSpacing: 18,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: [
        for (final item in _items)
          GestureDetector(
            onLongPress: item.canRemove
                ? () => _confirmRemove(item.playlist.displayTitle, item.origin == _BrowseOrigin.mine,
                    () => _removePlaylist(item))
                : null,
            child: CatalogTile(
              cover: item.playlist.cover,
              mosaic: item.playlist.artTiles,
              title: item.playlist.displayTitle,
              subtitle: _playlistSubtitle(item),
              platform: item.platform,
              route: PlaylistRoute(platform: item.platform, id: item.playlist.id, kind: item.kind, fromLibrary: true),
            ),
          ),
      ],
    );
  }

  String _playlistSubtitle(_BrowsePlaylist item) {
    final n = item.playlist.trackCount ?? 0;
    if (item.pinned) return n > 0 ? '收藏的歌曲 · $n 首' : '收藏的歌曲';
    if (item.kind == ListKind.mine) return n > 0 ? '播放列表 · $n 首' : '播放列表';
    final plat = MX.label(item.platform);
    return n > 0 ? '$plat · $n 首' : plat;
  }

  Widget _albumGrid() {
    if (_albums.isEmpty) return _empty(Icons.album, '还没有收藏专辑', '在专辑页点收藏后会出现在这里');
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 0.72,
      crossAxisSpacing: 14,
      mainAxisSpacing: 18,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: [
        for (final a in _albums)
          GestureDetector(
            onLongPress: () => _confirmRemove(a.displayTitle, false, () => _removeAlbum(a)),
            child: CatalogTile(
              cover: a.cover,
              title: a.displayTitle,
              subtitle: a.artistText,
              platform: a.platform,
              route: AlbumRoute(platform: a.platform, id: a.id),
            ),
          ),
      ],
    );
  }

  Widget _artistList() {
    if (_artists.isEmpty) return _empty(Icons.mic_none, '还没有收藏艺人', '在艺人页点收藏后会出现在这里');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: _artists.length,
      itemBuilder: (_, i) {
        final a = _artists[i];
        return Dismissible(
          key: ValueKey('artist:${a.platform}:${a.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            _removeArtist(a);
            return false;
          },
          background: Container(color: Colors.red.withOpacity(0.2)),
          child: CatalogListRow(
            cover: a.cover,
            title: a.displayName,
            subtitle: '艺人',
            platform: a.platform,
            route: ArtistRoute(platform: a.platform, id: a.id),
            circle: true,
          ),
        );
      },
    );
  }

  Widget _songList() {
    if (_tracks.isEmpty) return _empty(Icons.music_note, '还没有收藏歌曲', '把喜欢的歌曲收藏后会出现在这里');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: _tracks.length,
      itemBuilder: (_, i) => TrackRow(track: _tracks[i], index: i, queue: _tracks),
    );
  }
}

// ---------------------------------------------------------------------------
// RecentsView — history browser with segmented tabs. Mirrors Swift `RecentsView`.
// ---------------------------------------------------------------------------

class RecentsView extends StatefulWidget {
  const RecentsView({super.key});

  @override
  State<RecentsView> createState() => _RecentsViewState();
}

class _RecentsViewState extends State<RecentsView> {
  String _tab = 'track';
  List<Track> _tracks = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  List<Playlist> _playlists = [];
  bool _loading = true;
  bool _playingAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  bool get _isEmpty {
    switch (_tab) {
      case 'album':
        return _albums.isEmpty;
      case 'artist':
        return _artists.isEmpty;
      case 'playlist':
        return _playlists.isEmpty;
      default:
        return _tracks.isEmpty;
    }
  }

  String get _emptyLabel {
    switch (_tab) {
      case 'album':
        return '暂无最近专辑';
      case 'artist':
        return '暂无最近艺人';
      case 'playlist':
        return '暂无最近歌单';
      default:
        return '暂无播放记录';
    }
  }

  IconData get _emptyIcon {
    switch (_tab) {
      case 'album':
        return Icons.album;
      case 'artist':
        return Icons.person_outline;
      case 'playlist':
        return Icons.queue_music;
      default:
        return Icons.history;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = _isEmpty);
    final session = context.read<SessionStore>();
    switch (_tab) {
      case 'album':
        final cached = session.peekPage('recents.album', (m) => ItemsBox.fromJson(m, Album.fromJson));
        if (_albums.isEmpty && cached != null) _albums = cached.items ?? [];
        final box = await session.fetchPage('/api/me/history?kind=album&limit=80',
            cacheKey: 'recents.album', factory: (m) => ItemsBox.fromJson(m, Album.fromJson));
        if (box != null) _albums = box.items ?? [];
        break;
      case 'artist':
        final cached = session.peekPage('recents.artist', (m) => ItemsBox.fromJson(m, Artist.fromJson));
        if (_artists.isEmpty && cached != null) _artists = cached.items ?? [];
        final box = await session.fetchPage('/api/me/history?kind=artist&limit=80',
            cacheKey: 'recents.artist', factory: (m) => ItemsBox.fromJson(m, Artist.fromJson));
        if (box != null) _artists = box.items ?? [];
        break;
      case 'playlist':
        final cached = session.peekPage('recents.playlist', (m) => ItemsBox.fromJson(m, Playlist.fromJson));
        if (_playlists.isEmpty && cached != null) _playlists = cached.items ?? [];
        final box = await session.fetchPage('/api/me/history?kind=playlist&limit=80',
            cacheKey: 'recents.playlist', factory: (m) => ItemsBox.fromJson(m, Playlist.fromJson));
        if (box != null) _playlists = box.items ?? [];
        break;
      default:
        final cached = session.peekPage('recents.track', HistoryPayload.fromJson);
        if (_tracks.isEmpty && cached != null) {
          _tracks = (cached.items ?? []).map((t) => t..historyReplay = true).toList();
        }
        final box = await session.fetchPage('/api/me/history?kind=track&limit=80',
            cacheKey: 'recents.track', factory: HistoryPayload.fromJson);
        if (box != null) _tracks = (box.items ?? []).map((t) => t..historyReplay = true).toList();
        break;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _playAll() async {
    if (_playingAll) return;
    setState(() => _playingAll = true);
    final session = context.read<SessionStore>();
    final player = context.read<PlayerStore>();
    try {
      if (_tab == 'track') {
        await player.replaceQueue(_tracks, start: 0);
        return;
      }
      final raw = await session.api.getRawBody('/api/me/history/tracks?kind=$_tab');
      final box = APIClient.decodeCached(raw, HistoryPayload.fromJson);
      await player.replaceQueue(box?.tracks ?? [], start: 0);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _playingAll = false);
    }
  }

  Future<void> _clearAll() async {
    final session = context.read<SessionStore>();
    try {
      await session.api.delete('/api/me/history');
    } catch (_) {}
    setState(() {
      _tracks = [];
      _albums = [];
      _artists = [];
      _playlists = [];
    });
  }

  void _confirmClear() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('清空最近播放？', style: TextStyle(color: MX.fg)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearAll();
            },
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTrack(Track t) async {
    final session = context.read<SessionStore>();
    try {
      await session.api.delete('/api/me/history/track?platform=${t.platform}&id=${t.id}');
    } catch (_) {}
    setState(() => _tracks.removeWhere((x) => x.id == t.id && x.platform == t.platform));
  }

  Future<void> _deleteAlbum(Album a) async {
    final session = context.read<SessionStore>();
    try {
      await session.api.delete('/api/me/history/album?platform=${a.platform}&id=${a.id}');
    } catch (_) {}
    setState(() => _albums.removeWhere((x) => x.id == a.id && x.platform == a.platform));
  }

  Future<void> _deleteArtist(Artist a) async {
    final session = context.read<SessionStore>();
    try {
      await session.api.delete('/api/me/history/artist?platform=${a.platform}&id=${a.id}');
    } catch (_) {}
    setState(() => _artists.removeWhere((x) => x.id == a.id && x.platform == a.platform));
  }

  Future<void> _deletePlaylist(Playlist p) async {
    final session = context.read<SessionStore>();
    final plat = p.platform ?? 'local';
    try {
      await session.api.delete('/api/me/history/playlist?platform=$plat&id=${p.id}');
    } catch (_) {}
    setState(() => _playlists.removeWhere((x) => x.id == p.id && (x.platform ?? 'local') == plat));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MX.ink,
      appBar: AppBar(
        backgroundColor: MX.ink,
        surfaceTintColor: Colors.transparent,
        title: Text('最近播放', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
        actions: [
          if (!_isEmpty && !_loading) ...[
            IconButton(
                icon: Icon(Icons.play_arrow, color: _playingAll ? MX.dim : MX.fg),
                onPressed: _playingAll ? null : _playAll),
            TextButton(onPressed: _confirmClear, child: const Text('清空', style: TextStyle(color: Colors.red))),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: SegmentBar(
              items: const [('track', '歌曲'), ('album', '专辑'), ('artist', '艺人'), ('playlist', '歌单')],
              selected: _tab,
              onChanged: (next) {
                if (next == _tab) return;
                setState(() => _tab = next);
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: MX.ember))
                : _isEmpty
                    ? _emptyBody()
                    : RefreshIndicator(
                        color: MX.ember,
                        backgroundColor: MX.panel,
                        onRefresh: _load,
                        child: _content(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBody() => ListView(
        children: [
          const SizedBox(height: 80),
          Icon(_emptyIcon, color: MX.dim, size: 48),
          const SizedBox(height: 12),
          Center(child: Text(_emptyLabel, style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Center(child: Text('播放后会出现在这里', style: TextStyle(color: MX.dim, fontSize: 13))),
        ],
      );

  Widget _content() {
    switch (_tab) {
      case 'album':
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          itemCount: _albums.length,
          itemBuilder: (_, i) {
            final a = _albums[i];
            return Dismissible(
              key: ValueKey('r-album:${a.platform}:${a.id}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => _deleteAlbum(a),
              background: Container(color: Colors.red.withOpacity(0.2)),
              child: CatalogListRow(
                cover: a.cover,
                title: a.displayTitle,
                subtitle: a.artistText,
                platform: a.platform,
                route: AlbumRoute(platform: a.platform, id: a.id),
              ),
            );
          },
        );
      case 'artist':
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          itemCount: _artists.length,
          itemBuilder: (_, i) {
            final a = _artists[i];
            return Dismissible(
              key: ValueKey('r-artist:${a.platform}:${a.id}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => _deleteArtist(a),
              background: Container(color: Colors.red.withOpacity(0.2)),
              child: CatalogListRow(
                cover: a.cover,
                title: a.displayName,
                subtitle: '艺人',
                platform: a.platform,
                route: ArtistRoute(platform: a.platform, id: a.id),
                circle: true,
              ),
            );
          },
        );
      case 'playlist':
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          itemCount: _playlists.length,
          itemBuilder: (_, i) {
            final p = _playlists[i];
            return Dismissible(
              key: ValueKey('r-playlist:${p.platform ?? 'local'}:${p.id}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => _deletePlaylist(p),
              background: Container(color: Colors.red.withOpacity(0.2)),
              child: CatalogListRow(
                cover: p.cover,
                mosaic: p.artTiles,
                title: p.displayTitle,
                subtitle: '${p.trackCount ?? 0} 首',
                platform: p.platform,
                route: _playlistRoute(p, fromLibrary: false),
              ),
            );
          },
        );
      default:
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          itemCount: _tracks.length,
          itemBuilder: (_, i) {
            final t = _tracks[i];
            return Dismissible(
              key: ValueKey('r-track:${t.key}:$i'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => _deleteTrack(t),
              background: Container(color: Colors.red.withOpacity(0.2)),
              child: TrackRow(track: t, index: i, queue: _tracks, onDelete: () => _deleteTrack(t)),
            );
          },
        );
    }
  }
}

/// Square cover + two text lines skeleton. Mirrors Swift `CoverCardSkeleton`.
class _CoverCardSkeleton extends StatelessWidget {
  const _CoverCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: const SkeletonBar(height: 400, corner: 8),
          ),
        ),
        const SizedBox(height: 8),
        const SkeletonBar(width: 120, height: 14),
        const SizedBox(height: 6),
        const SkeletonBar(width: 80, height: 12),
      ],
    );
  }
}
