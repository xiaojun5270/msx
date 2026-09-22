import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/artwork_color.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';

String _enc(String s) => Uri.encodeComponent(s);

/// Blurred-cover hero page scaffold shared by the three detail views.
class _HeroScaffold extends StatelessWidget {
  final String title;
  final Color theme;
  final String? cover;
  final List<String>? mosaic;
  final Widget child;
  final List<Widget> menu;

  const _HeroScaffold({
    required this.title,
    required this.theme,
    required this.cover,
    this.mosaic,
    required this.child,
    this.menu = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MX.ink,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
        actions: [
          if (menu.isNotEmpty)
            PopupMenuButton<int>(
              icon: const Icon(Icons.more_horiz),
              color: MX.panel,
              itemBuilder: (_) => [
                for (var i = 0; i < menu.length; i++) PopupMenuItem(value: i, child: menu[i]),
              ],
              onSelected: (i) {
                final item = menu[i];
                if (item is _MenuAction) item.onTap();
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [theme.withOpacity(0.55), MX.ink],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A menu row with an inline action, used in the hero popup menu.
class _MenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const _MenuAction(this.icon, this.label, this.onTap, {this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.red : MX.fg;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PlaylistDetailView
// ---------------------------------------------------------------------------

class PlaylistDetailView extends StatefulWidget {
  final String platform;
  final String id;
  final ListKind kind;
  final bool fromLibrary;
  const PlaylistDetailView(
      {super.key, required this.platform, required this.id, required this.kind, this.fromLibrary = false});

  @override
  State<PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends State<PlaylistDetailView> {
  Playlist? _playlist;
  bool _loading = true;
  bool _fav = false;
  Color _theme = MX.heroBase;
  bool _ingesting = false;
  bool _syncing = false;
  SubscriptionState? _subState;
  Set<String> _newIds = {};

  List<Track> get _tracks => _playlist?.tracks ?? [];
  List<Track> get _ingestible => _tracks.where(LibraryIngest.canIngest).toList();
  String? get _cover => _playlist?.coverUrl ?? _playlist?.artworkUrl ?? (_tracks.isNotEmpty ? _tracks.first.cover : null);
  bool get _canFavorite => _playlist != null && _playlist?.kind != 'favorites';
  bool get _canIngest => _ingestible.isNotEmpty;
  bool get _canSubscribe => widget.kind == ListKind.chart || widget.kind == ListKind.platform;
  bool get _canDelete => widget.kind == ListKind.mine && _playlist?.kind != 'favorites';
  String get _entityPlatform => _playlist?.platform ?? (widget.kind == ListKind.mine ? 'local' : widget.platform);
  String get _entityId => _playlist?.id ?? widget.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  PlaySource get _source => PlaySource(
        kind: 'playlist',
        platform: _playlist?.platform ?? (widget.kind == ListKind.mine ? 'local' : widget.platform),
        id: _playlist?.id ?? widget.id,
        title: _playlist?.displayTitle,
        coverUrl: _cover,
        motionUrl: _playlist?.motionUrl,
        mosaicUrls: _playlist?.mosaicUrls,
        listKind: widget.kind.name,
        trackCount: _tracks.length,
      );

  Future<void> _load({bool refresh = false}) async {
    final session = context.read<SessionStore>();
    if (_playlist == null) setState(() => _loading = true);
    switch (widget.kind) {
      case ListKind.mine:
        final key = 'detail.playlist.mine.${widget.id}';
        final cached = session.peekPage(key, PlaylistBox.fromJson);
        if (_playlist == null && cached?.playlist != null) _playlist = cached!.playlist;
        final box = await session.fetchPage('/api/my/playlists/${widget.id}', cacheKey: key, factory: PlaylistBox.fromJson);
        if (box?.playlist != null) _playlist = box!.playlist;
        break;
      case ListKind.chart:
        final key = 'detail.playlist.chart.${widget.platform}.${widget.id}';
        final cached = session.peekPage(key, Playlist.fromJson);
        if (_playlist == null && cached != null) _playlist = cached;
        final p = await session.fetchPage('/api/charts/${widget.platform}/${widget.id}', cacheKey: key, factory: Playlist.fromJson);
        if (p != null) _playlist = p;
        break;
      case ListKind.platform:
        final enc = _enc(widget.id);
        final key = 'detail.playlist.platform.${widget.platform}.${widget.id}';
        final cached = session.peekPage(key, Playlist.fromJson);
        if (_playlist == null && cached != null) _playlist = cached;
        final path = refresh
            ? '/api/playlists/${widget.platform}/$enc?refresh=1'
            : '/api/playlists/${widget.platform}/$enc';
        final p = await session.fetchPage(path, cacheKey: key, factory: Playlist.fromJson);
        if (p != null) _playlist = p;
        break;
    }
    await _loadFav(session);
    await _loadSubState(session);
    if (mounted) setState(() => _loading = false);
    _loadTheme(session);
  }

  Future<void> _loadTheme(SessionStore session) async {
    final c = await ArtworkColor.load(_cover, session.api);
    if (mounted) setState(() => _theme = c);
  }

  Future<void> _loadFav(SessionStore session) async {
    if (!_canFavorite) {
      _fav = false;
      return;
    }
    try {
      final box = await session.api.getJson(
          '/api/my/favorites/items?kind=playlist&platform=${_enc(_entityPlatform)}&id=${_enc(_entityId)}',
          (m) => ItemsBox.fromJson(m, Playlist.fromJson));
      _fav = box.has ?? false;
    } catch (_) {}
  }

  Future<void> _loadSubState(SessionStore session) async {
    if (!_canSubscribe) return;
    final k = widget.kind == ListKind.chart ? 'chart' : 'playlist';
    try {
      _subState = await session.api.getJson(
          '/api/subscriptions/lookup?platform=${_enc(_entityPlatform)}&sourceId=${_enc(_entityId)}&kind=$k',
          SubscriptionState.fromJson);
      final subId = _subState?.id;
      if (subId != null) {
        final sub = await session.api.getJson('/api/subscriptions/$subId', Subscription.fromJson);
        final ids = <String>{};
        for (final t in sub.tracks ?? []) {
          if (t.isNew == true) ids.add(t.id);
        }
        _newIds = ids;
      }
    } catch (_) {}
  }

  Future<void> _playShuffled() async {
    final player = context.read<PlayerStore>();
    if (!player.shuffle) player.toggleShuffle();
    await player.replaceQueue(_tracks, start: 0, source: _source);
  }

  Future<void> _toggleFav() async {
    if (!_canFavorite) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    final body = <String, dynamic>{
      'kind': 'playlist',
      'id': _entityId,
      'platform': _entityPlatform,
      'title': _playlist?.displayTitle ?? '',
      'listKind': widget.kind.name,
      'trackCount': _tracks.length,
    };
    if (_cover != null) {
      body['coverUrl'] = _cover;
      body['artworkUrl'] = _cover;
    }
    final mosaic = _playlist?.mosaicUrls;
    if (mosaic != null && mosaic.isNotEmpty) body['mosaicUrls'] = mosaic;
    if (_playlist?.motionUrl != null) body['motionUrl'] = _playlist!.motionUrl;
    try {
      final data = await session.api.postJson('/api/my/favorites/items/toggle', FavToggle.fromJson, json: body);
      setState(() => _fav = data.favorited ?? data.has ?? !_fav);
      ui.notify(_fav ? '已收藏' : '已取消收藏');
    } catch (_) {}
  }

  Future<void> _subscribe() async {
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    final body = <String, dynamic>{
      'platform': _entityPlatform,
      'sourceId': _entityId,
      'kind': widget.kind == ListKind.chart ? 'chart' : 'playlist',
      'title': _playlist?.displayTitle ?? '',
      'trackCount': _tracks.length,
    };
    if (_cover != null) body['coverUrl'] = _cover;
    try {
      final sub = await session.api.postJson('/api/subscriptions', Subscription.fromJson, json: body);
      setState(() => _subState = SubscriptionState(
          subscribed: true, id: sub.id, refreshEnabled: sub.refreshEnabled, ingestEnabled: sub.ingestEnabled));
      ui.notify('已订阅');
    } catch (e) {
      ui.notify('$e');
    }
  }

  Future<void> _unsubscribe() async {
    final id = _subState?.id;
    if (id == null) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      await session.api.delete('/api/subscriptions/$id');
      setState(() => _subState = const SubscriptionState(subscribed: false));
      ui.notify('已取消订阅');
    } catch (e) {
      ui.notify('$e');
    }
  }

  Future<void> _syncSubscription() async {
    final id = _subState?.id;
    if (id == null) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    setState(() => _syncing = true);
    try {
      await session.api.post('/api/subscriptions/$id/sync');
      ui.notify('同步完成');
      await _loadSubState(session);
      if (mounted) setState(() {});
    } catch (e) {
      ui.notify('$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _ingestAll() async {
    if (!_canIngest || _ingesting) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    setState(() => _ingesting = true);
    try {
      final result = await session.api.postJson('/api/library/ingest/batch', IngestBatchResult.fromJson,
          json: {'items': LibraryIngest.items(_ingestible)});
      ui.notify(result.message);
    } catch (e) {
      ui.notify('$e');
    } finally {
      if (mounted) setState(() => _ingesting = false);
    }
  }

  Future<void> _deletePlaylist() async {
    if (!_canDelete) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      await session.api.delete('/api/my/playlists/${widget.id}');
      ui.notify('歌单已解散');
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      ui.notify('$e');
    }
  }

  Future<void> _removeTrack(Track track) async {
    if (!_canDelete) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      await session.api.delete('/api/my/playlists/${widget.id}/tracks/${_enc(track.platform)}/${_enc(track.id)}');
      setState(() => _playlist?.tracks?.removeWhere((t) => t.key == track.key));
      ui.notify('已从歌单移除');
    } catch (e) {
      ui.notify('$e');
    }
  }

  void _confirmIngest() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('将 ${_ingestible.length} 首歌曲入库到本地？', style: TextStyle(color: MX.fg, fontSize: 17)),
        content: Text('按最高可用完整音质入库，不使用试听文件。已入库曲目会跳过；失败可在入库记录中重试。',
            style: TextStyle(color: MX.dim, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () { Navigator.pop(ctx); _ingestAll(); }, child: const Text('入库')),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('确定解散此歌单？', style: TextStyle(color: MX.fg, fontSize: 17)),
        content: Text('所有歌曲将被移除，此操作不可撤销。', style: TextStyle(color: MX.dim, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () { Navigator.pop(ctx); _deletePlaylist(); },
              child: const Text('解散歌单', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  String get _subtitle {
    final plat = MX.label(_playlist?.platform ?? widget.platform);
    final n = _playlist?.trackCount ?? _tracks.length;
    return n > 0 ? '$plat · $n 首' : plat;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    final ui = context.read<UIStore>();
    final title = _playlist?.displayTitle ?? '歌单';
    final menu = <Widget>[
      if (_canFavorite) _MenuAction(_fav ? Icons.heart_broken : Icons.favorite_border, _fav ? '取消收藏' : '收藏', _toggleFav),
      if (_canSubscribe)
        _subState?.subscribed == true
            ? _MenuAction(Icons.notifications_off, '取消订阅', _unsubscribe, destructive: true)
            : _MenuAction(Icons.notifications, '订阅', _subscribe),
      if (_subState?.subscribed == true) _MenuAction(Icons.refresh, _syncing ? '同步中…' : '同步', _syncSubscription),
      if (_canIngest) _MenuAction(Icons.download, _ingesting ? '入库中…' : '一键入库', _confirmIngest),
      if (_canDelete) _MenuAction(Icons.delete, '解散歌单', _confirmDelete, destructive: true),
      if (_tracks.isNotEmpty) _MenuAction(Icons.graphic_eq, '整理音源', () => ui.openOrganization(_tracks)),
      if (_tracks.isNotEmpty) _MenuAction(Icons.play_arrow, '播放', () => player.replaceQueue(_tracks, start: 0, source: _source)),
      if (_tracks.isNotEmpty) _MenuAction(Icons.shuffle, '随机播放', _playShuffled),
    ];
    return _HeroScaffold(
      title: title,
      theme: _theme,
      cover: _cover,
      mosaic: _playlist?.artTiles,
      menu: menu,
      child: RefreshIndicator(
        color: MX.ember,
        backgroundColor: MX.panel,
        onRefresh: () => _load(refresh: true),
        child: (_loading && _playlist == null)
            ? ListView(children: [const SizedBox(height: 120), Center(child: CircularProgressIndicator(color: MX.ember))])
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  CollectionHero(
                    cover: _cover,
                    mosaic: _playlist?.artTiles,
                    title: title,
                    subtitle: _subtitle,
                    canPlay: _tracks.isNotEmpty,
                    plusIcon: _fav ? Icons.check : Icons.add,
                    onPlay: () => player.replaceQueue(_tracks, start: 0, source: _source),
                    onShuffle: _playShuffled,
                    onPlus: _canFavorite ? _toggleFav : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      children: [
                        for (var i = 0; i < _tracks.length; i++)
                          CatalogTrackRow(
                            track: _tracks[i],
                            index: i,
                            queue: _tracks,
                            onRemove: _canDelete ? (t) => _removeTrack(t) : null,
                            isNew: _newIds.contains(_tracks[i].id),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AlbumDetailView
// ---------------------------------------------------------------------------

class AlbumDetailView extends StatefulWidget {
  final String platform;
  final String id;
  const AlbumDetailView({super.key, required this.platform, required this.id});

  @override
  State<AlbumDetailView> createState() => _AlbumDetailViewState();
}

class _AlbumDetailViewState extends State<AlbumDetailView> {
  Album? _album;
  bool _loading = true;
  bool _fav = false;
  Color _theme = MX.heroBase;
  bool _ingesting = false;

  List<Track> get _tracks => _album?.tracks ?? [];
  List<Track> get _ingestible => _tracks.where(LibraryIngest.canIngest).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  PlaySource get _source => PlaySource(
        kind: 'album',
        platform: _album?.platform ?? widget.platform,
        id: _album?.id ?? widget.id,
        title: _album?.displayTitle,
        artists: _album?.artists,
        coverUrl: _album?.coverUrl ?? _album?.artworkUrl,
        artworkUrl: _album?.artworkUrl ?? _album?.coverUrl,
      );

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    if (_album == null) setState(() => _loading = true);
    final enc = _enc(widget.id);
    final key = 'detail.album.${widget.platform}.${widget.id}';
    final cached = session.peekPage(key, Album.fromJson);
    if (_album == null && cached != null) _album = cached;
    final a = await session.fetchPage('/api/albums/${widget.platform}/$enc', cacheKey: key, factory: Album.fromJson);
    if (a != null) _album = a;
    try {
      final box = await session.api.getJson(
          '/api/my/favorites/items?kind=album&platform=${widget.platform}&id=$enc',
          (m) => ItemsBox.fromJson(m, Album.fromJson));
      _fav = box.has ?? _fav;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    final c = await ArtworkColor.load(_album?.cover, session.api);
    if (mounted) setState(() => _theme = c);
  }

  Future<void> _playShuffled() async {
    final player = context.read<PlayerStore>();
    if (!player.shuffle) player.toggleShuffle();
    await player.replaceQueue(_tracks, start: 0, source: _source);
  }

  Future<void> _toggleFav() async {
    final album = _album;
    if (album == null) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    final body = <String, dynamic>{'kind': 'album', 'id': album.id, 'platform': album.platform, 'title': album.displayTitle};
    if (album.cover != null) body['artworkUrl'] = album.cover;
    try {
      final data = await session.api.postJson('/api/my/favorites/items/toggle', FavToggle.fromJson, json: body);
      setState(() => _fav = data.favorited ?? data.has ?? !_fav);
      ui.notify(_fav ? '已收藏' : '已取消收藏');
    } catch (_) {}
  }

  Future<void> _ingestAll() async {
    if (_ingesting || _ingestible.isEmpty) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    setState(() => _ingesting = true);
    try {
      final result = await session.api.postJson('/api/library/ingest/batch', IngestBatchResult.fromJson,
          json: {'items': LibraryIngest.items(_ingestible)});
      ui.notify(result.message);
    } catch (e) {
      ui.notify('$e');
    } finally {
      if (mounted) setState(() => _ingesting = false);
    }
  }

  void _confirmIngest() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('将 ${_ingestible.length} 首歌曲入库到本地？', style: TextStyle(color: MX.fg, fontSize: 17)),
        content: Text('按最高可用完整音质入库，不使用试听文件。已入库曲目会跳过；失败可在入库记录中重试。',
            style: TextStyle(color: MX.dim, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () { Navigator.pop(ctx); _ingestAll(); }, child: const Text('入库')),
        ],
      ),
    );
  }

  String get _subtitle {
    final artist = _album?.artistText ?? '';
    final plat = MX.label(widget.platform);
    return artist.isEmpty ? plat : '$artist · $plat';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    final ui = context.read<UIStore>();
    final title = _album?.displayTitle ?? '专辑';
    final menu = <Widget>[
      _MenuAction(_fav ? Icons.check : Icons.favorite_border, _fav ? '取消收藏' : '收藏', _toggleFav),
      if (_tracks.isNotEmpty) _MenuAction(Icons.graphic_eq, '整理音源', () => ui.openOrganization(_tracks)),
      if (_ingestible.isNotEmpty) _MenuAction(Icons.download, _ingesting ? '入库中…' : '一键入库', _confirmIngest),
      if (_tracks.isNotEmpty) _MenuAction(Icons.play_arrow, '播放', () => player.replaceQueue(_tracks, start: 0, source: _source)),
      if (_tracks.isNotEmpty) _MenuAction(Icons.shuffle, '随机播放', _playShuffled),
    ];
    return _HeroScaffold(
      title: title,
      theme: _theme,
      cover: _album?.cover,
      menu: menu,
      child: (_loading && _album == null)
          ? ListView(children: [const SizedBox(height: 120), Center(child: CircularProgressIndicator(color: MX.ember))])
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                CollectionHero(
                  cover: _album?.cover,
                  title: title,
                  subtitle: _subtitle,
                  canPlay: _tracks.isNotEmpty,
                  plusIcon: _fav ? Icons.check : Icons.add,
                  onPlay: () => player.replaceQueue(_tracks, start: 0, source: _source),
                  onShuffle: _playShuffled,
                  onPlus: _toggleFav,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    children: [
                      for (var i = 0; i < _tracks.length; i++)
                        CatalogTrackRow(track: _tracks[i], index: i, queue: _tracks),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// ArtistDetailView
// ---------------------------------------------------------------------------

class ArtistDetailView extends StatefulWidget {
  final String platform;
  final String id;
  const ArtistDetailView({super.key, required this.platform, required this.id});

  @override
  State<ArtistDetailView> createState() => _ArtistDetailViewState();
}

class _ArtistDetailViewState extends State<ArtistDetailView> {
  Artist? _artist;
  bool _loading = true;
  bool _fav = false;
  Color _theme = MX.heroBase;

  List<Track> get _tracks => _artist?.tracks ?? [];
  List<Album> get _albums => _artist?.albums ?? [];
  String? get _cover => _artist?.cover;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  PlaySource get _source => PlaySource(
        kind: 'artist',
        platform: _artist?.platform ?? widget.platform,
        id: _artist?.id ?? widget.id,
        title: _artist?.displayName,
        name: _artist?.displayName,
        coverUrl: _artist?.coverUrl ?? _artist?.cover,
        artworkUrl: _artist?.artworkUrl ?? _artist?.cover,
        avatarUrl: _artist?.cover,
      );

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    if (_artist == null) setState(() => _loading = true);
    final enc = _enc(widget.id);
    final key = 'detail.artist.${widget.platform}.${widget.id}';
    final cached = session.peekPage(key, Artist.fromJson);
    if (_artist == null && cached != null) _artist = cached;
    final a = await session.fetchPage('/api/artists/${widget.platform}/$enc', cacheKey: key, factory: Artist.fromJson);
    if (a != null) _artist = a;
    try {
      final box = await session.api.getJson(
          '/api/my/favorites/items?kind=artist&platform=${widget.platform}&id=$enc',
          (m) => ItemsBox.fromJson(m, Artist.fromJson));
      _fav = box.has ?? _fav;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    final c = await ArtworkColor.load(_cover, session.api);
    if (mounted) setState(() => _theme = c);
  }

  Future<void> _playShuffled() async {
    final player = context.read<PlayerStore>();
    if (!player.shuffle) player.toggleShuffle();
    await player.replaceQueue(_tracks, start: 0, source: _source);
  }

  Future<void> _toggleFav() async {
    final artist = _artist;
    if (artist == null) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    final body = <String, dynamic>{'kind': 'artist', 'id': artist.id, 'platform': artist.platform, 'name': artist.displayName};
    if (artist.cover != null) body['avatarUrl'] = artist.cover;
    try {
      final data = await session.api.postJson('/api/my/favorites/items/toggle', FavToggle.fromJson, json: body);
      setState(() => _fav = data.favorited ?? data.has ?? !_fav);
      ui.notify(_fav ? '已收藏' : '已取消收藏');
    } catch (_) {}
  }

  String get _subtitle {
    final plat = MX.label(widget.platform);
    final n = _tracks.length;
    return n > 0 ? '$plat · $n 首' : plat;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    final ui = context.read<UIStore>();
    final title = _artist?.displayName ?? '艺人';
    final menu = <Widget>[
      _MenuAction(_fav ? Icons.check : Icons.favorite_border, _fav ? '取消收藏' : '收藏', _toggleFav),
      if (_tracks.isNotEmpty) _MenuAction(Icons.play_arrow, '播放', () => player.replaceQueue(_tracks, start: 0, source: _source)),
      if (_tracks.isNotEmpty) _MenuAction(Icons.shuffle, '随机播放', _playShuffled),
    ];
    return _HeroScaffold(
      title: title,
      theme: _theme,
      cover: _cover,
      menu: menu,
      child: (_loading && _artist == null)
          ? ListView(children: [const SizedBox(height: 120), Center(child: CircularProgressIndicator(color: MX.ember))])
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                CollectionHero(
                  cover: _cover,
                  title: title,
                  subtitle: _subtitle,
                  canPlay: _tracks.isNotEmpty,
                  plusIcon: _fav ? Icons.check : Icons.add,
                  onPlay: () => player.replaceQueue(_tracks, start: 0, source: _source),
                  onShuffle: _playShuffled,
                  onPlus: _toggleFav,
                  circle: true,
                ),
                if (_tracks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (var i = 0; i < _tracks.length; i++)
                          CatalogTrackRow(track: _tracks[i], index: i, queue: _tracks),
                      ],
                    ),
                  ),
                if (_albums.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, _tracks.isEmpty ? 0 : 20, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('专辑', style: TextStyle(color: MX.fg, fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SizedBox(
                    height: 190,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _albums.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final a = _albums[i];
                        return GestureDetector(
                          onTap: () => ui.open(AlbumRoute(platform: a.platform, id: a.id)),
                          child: SizedBox(
                            width: 140,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CoverArt(src: a.cover, size: 140, corner: 8),
                                const SizedBox(height: 8),
                                Text(a.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
