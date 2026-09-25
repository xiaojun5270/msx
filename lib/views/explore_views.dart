import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';

String _enc(String s) => Uri.encodeComponent(s);

// ---------------------------------------------------------------------------
// GenresView —曲风 grid
// ---------------------------------------------------------------------------

class GenresView extends StatefulWidget {
  const GenresView({super.key});
  @override
  State<GenresView> createState() => _GenresViewState();
}

class _GenresViewState extends State<GenresView> {
  List<Genre> _genres = [];
  String _platform = 'all';
  bool _loading = true;

  List<String> get _platforms =>
      (_genres.map((g) => g.platform).where((p) => p.isNotEmpty).toSet().toList()..sort());
  List<Genre> get _shown => _platform == 'all' ? _genres : _genres.where((g) => g.platform == _platform).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    if (_genres.isEmpty) {
      final cached = session.peekPage('explore.genres', GenreListResult.fromJson);
      if (cached != null && cached.items.isNotEmpty) _genres = cached.items;
    }
    if (_genres.isEmpty) _genres = Genre.commonCatalog;
    if (mounted) setState(() => _loading = _genres.isEmpty);
    final fresh = await session.fetchPage('/api/genres', cacheKey: 'explore.genres', factory: GenreListResult.fromJson);
    if (fresh != null && fresh.items.isNotEmpty) _genres = fresh.items;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.read<UIStore>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text('曲风', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text('从平台曲风中发现新的歌手与歌曲', style: TextStyle(color: MX.dim, fontSize: 14)),
          const SizedBox(height: 14),
          if (_platforms.length > 1) ...[
            ChipBar(
              items: [('all', '全部'), ..._platforms.map((p) => (p, MX.label(p)))],
              selected: _platform,
              onChanged: (v) => setState(() => _platform = v),
            ),
            const SizedBox(height: 14),
          ],
          if (_shown.isEmpty && !_loading)
            _emptyState(Icons.grid_view, '暂无曲风数据')
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                for (final g in _shown)
                  _GenreTile(genre: g, onTap: () => ui.open(GenreRoute(platform: g.platform, id: g.id))),
              ],
            ),
        ],
      ),
    );
  }
}

class _GenreTile extends StatelessWidget {
  final Genre genre;
  final VoidCallback onTap;
  const _GenreTile({required this.genre, required this.onTap});

  Color get _tint {
    switch (genre.id) {
      case 'common:pop':
      case 'common:chinese-pop':
        return const Color(0xFFF53870);
      case 'common:rock':
      case 'common:metal':
      case 'common:punk':
        return const Color(0xFFD13352);
      case 'common:hip-hop':
      case 'common:rap':
        return const Color(0xFF4D6EEB);
      case 'common:rnb':
      case 'common:soul':
        return const Color(0xFF925CD6);
      case 'common:electronic':
        return const Color(0xFF0DB094);
      case 'common:folk':
        return const Color(0xFFD17B2E);
      case 'common:classical':
      case 'common:jazz':
      case 'common:blues':
        return const Color(0xFF1F9CC7);
      case 'common:acg':
      case 'common:japanese-pop':
      case 'common:korean-pop':
        return const Color(0xFFB34AC7);
      default:
        return MX.ember;
    }
  }

  IconData get _icon {
    switch (genre.id) {
      case 'common:rock':
      case 'common:metal':
      case 'common:punk':
      case 'common:folk':
      case 'common:country':
        return Icons.music_note;
      case 'common:hip-hop':
      case 'common:rap':
      case 'common:rnb':
      case 'common:soul':
        return Icons.mic;
      case 'common:electronic':
        return Icons.graphic_eq;
      case 'common:classical':
      case 'common:jazz':
      case 'common:blues':
        return Icons.piano;
      case 'common:acg':
      case 'common:japanese-pop':
      case 'common:korean-pop':
        return Icons.auto_awesome;
      case 'common:easy-listening':
      case 'common:instrumental':
        return Icons.headphones;
      case 'common:soundtrack':
        return Icons.movie;
      default:
        return Icons.music_note;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_tint.withOpacity(0.98), _tint.withOpacity(0.68)],
          ),
          border: Border.all(color: MX.hairline, width: 0.5),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -8,
              top: 4,
              child: Transform.rotate(
                angle: -0.17,
                child: Icon(_icon, size: 72, color: Colors.white.withOpacity(0.18)),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(genre.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(genre.platform == 'catalog' ? '探索推荐' : MX.label(genre.platform),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 11, fontWeight: FontWeight.w500)),
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
// GenreDetailView
// ---------------------------------------------------------------------------

class GenreDetailView extends StatefulWidget {
  final String platform;
  final String id;
  const GenreDetailView({super.key, required this.platform, required this.id});
  @override
  State<GenreDetailView> createState() => _GenreDetailViewState();
}

class _GenreDetailViewState extends State<GenreDetailView> {
  GenreResult? _r;
  List<Track> _tracks = [];
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _key => 'explore.genre.${widget.platform}.${widget.id}';

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    final cached = session.peekPage(_key, GenreResult.fromJson);
    if (cached != null) _apply(cached);
    if (mounted) setState(() => _loading = _tracks.isEmpty);
    final path = '/api/genres/${_enc(widget.id)}?platform=${_enc(widget.platform)}&limit=30';
    final fresh = await session.fetchPage(path, cacheKey: _key, factory: GenreResult.fromJson);
    if (fresh != null) _apply(fresh);
    if (mounted) setState(() => _loading = false);
  }

  void _apply(GenreResult r) {
    _r = r;
    _tracks = r.tracks;
    _nextOffset = r.nextOffset ?? r.tracks.length;
    _hasMore = r.hasMore ?? false;
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final session = context.read<SessionStore>();
    final path = '/api/genres/${_enc(widget.id)}?platform=${_enc(widget.platform)}&limit=30&offset=$_nextOffset';
    try {
      final fresh = await session.api.getJson(path, GenreResult.fromJson);
      final keys = _tracks.map((t) => t.key).toSet();
      _tracks = [..._tracks, ...fresh.tracks.where((t) => !keys.contains(t.key))];
      _nextOffset = fresh.nextOffset ?? _tracks.length;
      _hasMore = fresh.hasMore ?? false;
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    final ui = context.read<UIStore>();
    final r = _r;
    final albums = r?.albums ?? [];
    final classic = r?.classicAlbums ?? [];
    final artists = r?.artists ?? [];
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(r?.genre?.name ?? '曲风推荐', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: _tracks.isEmpty ? null : () => player.replaceQueue(_tracks, start: 0),
                style: FilledButton.styleFrom(backgroundColor: MX.ember),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('播放推荐'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${_tracks.length} 首歌曲 · ${artists.length} 位艺人',
                    style: TextStyle(color: MX.dim, fontSize: 12)),
              ),
            ],
          ),
          if (r?.eraTracks.isNotEmpty ?? false) _trackShelf('年代代表作品', '跨越时间仍值得重听', r!.eraTracks, player),
          if (r?.annualTracks.isNotEmpty ?? false) _trackShelf('年度热门作品', '这一年最受关注的声音', r!.annualTracks, player),
          if (classic.isNotEmpty) _albumShelf('经典专辑', '值得完整聆听', classic, ui),
          if (albums.isNotEmpty) _albumShelf('推荐专辑', '适合继续深入聆听', albums, ui),
          if (artists.isNotEmpty) _artistShelf(artists, ui),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('推荐歌曲', style: TextStyle(color: MX.fg, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Text('按相关度排序', style: TextStyle(color: MX.dim, fontSize: 12)),
              const Spacer(),
              if (_tracks.isNotEmpty)
                TextButton(
                    onPressed: () => player.replaceQueue(_tracks, start: 0),
                    child: Text('播放全部', style: TextStyle(color: MX.ember))),
            ],
          ),
          if (_tracks.isEmpty && !_loading)
            _emptyState(Icons.music_note, '暂无推荐歌曲')
          else
            for (var i = 0; i < _tracks.length; i++) TrackRow(track: _tracks[i], index: i, queue: _tracks),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(_loadingMore ? '加载中…' : '加载更多'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trackShelf(String title, String subtitle, List<Track> tracks, PlayerStore player) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _shelfTitle(title, subtitle),
        const SizedBox(height: 10),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tracks.take(12).length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final t = tracks[i];
              return GestureDetector(
                onTap: () => player.replaceQueue(tracks, start: i),
                child: SizedBox(
                  width: 158,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverArt(src: t.cover, size: 158, corner: 14),
                      const SizedBox(height: 8),
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(t.artistText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MX.dim, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _albumShelf(String title, String subtitle, List<Album> albums, UIStore ui) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _shelfTitle(title, subtitle),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final a = albums[i];
              return GestureDetector(
                onTap: () => ui.open(AlbumRoute(platform: a.platform, id: a.id)),
                child: SizedBox(
                  width: 148,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverArt(src: a.cover, size: 148, corner: 14),
                      const SizedBox(height: 8),
                      Text(a.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(a.artistText.isEmpty ? MX.label(a.platform) : a.artistText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MX.dim, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _artistShelf(List<Artist> artists, UIStore ui) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _shelfTitle('推荐歌手', null),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final a = artists[i];
              return GestureDetector(
                onTap: () => ui.open(ArtistRoute(platform: a.platform, id: a.id)),
                child: SizedBox(
                  width: 78,
                  child: Column(
                    children: [
                      CoverArt(src: a.cover, size: 68, corner: 34, circle: true),
                      const SizedBox(height: 7),
                      Text(a.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MX.fg, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _shelfTitle(String title, String? subtitle) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: TextStyle(color: MX.fg, fontSize: 18, fontWeight: FontWeight.bold)),
          if (subtitle != null) ...[
            const SizedBox(width: 6),
            Text(subtitle, style: TextStyle(color: MX.dim, fontSize: 12)),
          ],
        ],
      );
}

// ---------------------------------------------------------------------------
// DailyView — 每日歌曲
// ---------------------------------------------------------------------------

class DailyView extends StatefulWidget {
  const DailyView({super.key});
  @override
  State<DailyView> createState() => _DailyViewState();
}

class _DailyViewState extends State<DailyView> {
  List<Track> _tracks = [];
  String _tab = 'all';
  bool _loading = true;

  List<String> get _plats =>
      (_tracks.map((t) => t.platform).where((p) => p.isNotEmpty).toSet().toList()..sort());
  List<Track> get _shown => _tab == 'all' ? _tracks : _tracks.where((t) => t.platform == _tab).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    if (_tracks.isEmpty) {
      final cached = session.peekPage('explore.daily.taste', HomeShelf.fromJson);
      if (cached != null) _tracks = _dailyTracks(cached);
    }
    if (mounted) setState(() => _loading = _tracks.isEmpty);
    final box = await session.fetchPage('/api/home/taste', cacheKey: 'explore.daily.taste', factory: HomeShelf.fromJson);
    if (box != null) _tracks = _dailyTracks(box);
    if (mounted) setState(() => _loading = false);
  }

  List<Track> _dailyTracks(HomeShelf box) {
    final raw = <Track>[
      ...(box.tracks ?? []),
      if (box.tracks == null) ...box.items?.expand((i) => i.tracks ?? []).toList() ?? [],
    ].where((t) => t.title.isNotEmpty).toList();
    return SourcePick.mix(raw, n: 200, platform: (t) => t.platform);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text('每日歌曲', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
        actions: [
          if (_shown.isNotEmpty)
            TextButton(
                onPressed: () => player.replaceQueue(_shown, start: 0),
                child: Text('播放全部', style: TextStyle(color: MX.ember))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          if (_plats.isNotEmpty) ...[
            ChipBar(
              items: [('all', '全部'), ..._plats.map((p) => (p, MX.label(p)))],
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
            const SizedBox(height: 12),
          ],
          if (_shown.isEmpty && !_loading)
            _emptyState(Icons.music_note, '暂无每日推荐')
          else
            for (var i = 0; i < _shown.length; i++) TrackRow(track: _shown[i], index: i, queue: _shown),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ExplorePlaylistsView — 歌单
// ---------------------------------------------------------------------------

class ExplorePlaylistsView extends StatefulWidget {
  const ExplorePlaylistsView({super.key});
  @override
  State<ExplorePlaylistsView> createState() => _ExplorePlaylistsViewState();
}

class _ExplorePlaylistsViewState extends State<ExplorePlaylistsView> {
  String _tab = 'all';
  List<Playlist> _publics = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    final key = 'explore.playlists.$_tab';
    final path = _tab == 'all' ? '/api/discover/playlists' : '/api/discover/playlists?platform=$_tab';
    if (_publics.isEmpty) {
      final cached = session.peekPage(key, DiscoverPlaylists.fromJson);
      if (cached != null) _publics = cached.public ?? [];
    }
    if (mounted) setState(() => _loading = _publics.isEmpty);
    final box = await session.fetchPage(path, cacheKey: key, factory: DiscoverPlaylists.fromJson);
    if (box != null) _publics = box.public ?? [];
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text('歌单', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          ChipBar(
            items: const [('all', '全部'), ('apple', 'Apple'), ('netease', '网易云'), ('qqmusic', 'QQ'), ('kugou', '酷狗')],
            selected: _tab,
            onChanged: (v) {
              setState(() {
                _tab = v;
                _publics = [];
              });
              _load();
            },
          ),
          const SizedBox(height: 14),
          if (_publics.isEmpty && !_loading)
            _emptyState(Icons.queue_music, '暂无歌单')
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.78,
              crossAxisSpacing: 16,
              mainAxisSpacing: 18,
              children: [
                for (final p in _publics)
                  CatalogTile(
                    cover: p.cover,
                    mosaic: p.artTiles,
                    title: p.displayTitle,
                    subtitle: '',
                    platform: p.platform ?? _tab,
                    route: PlaylistRoute(platform: p.platform ?? _tab, id: p.id, kind: ListKind.platform, fromLibrary: false),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ExploreAlbumsView — 新发行
// ---------------------------------------------------------------------------

class ExploreAlbumsView extends StatefulWidget {
  const ExploreAlbumsView({super.key});
  @override
  State<ExploreAlbumsView> createState() => _ExploreAlbumsViewState();
}

class _ExploreAlbumsViewState extends State<ExploreAlbumsView> {
  String _tab = 'all';
  List<FeedItem> _albums = [];
  bool _loading = true;

  List<String> get _plats =>
      (_albums.map((a) => a.platform ?? '').where((p) => p.isNotEmpty).toSet().toList()..sort());
  List<FeedItem> get _shown {
    final list = _tab == 'all' ? _albums : _albums.where((a) => a.platform == _tab).toList();
    return _tab == 'all' ? SourcePick.mix(list, n: 80, platform: (a) => a.platform ?? '') : list;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    if (_albums.isEmpty) {
      final cached = session.peekPage('explore.albums', DiscoverAlbums.fromJson);
      if (cached != null) _albums = _filter(session, cached.albums ?? []);
    }
    if (mounted) setState(() => _loading = _albums.isEmpty);
    final box = await session.fetchPage('/api/discover/albums', cacheKey: 'explore.albums', factory: DiscoverAlbums.fromJson);
    if (box != null) _albums = _filter(session, box.albums ?? []);
    if (mounted) setState(() => _loading = false);
  }

  List<FeedItem> _filter(SessionStore session, List<FeedItem> raw) => raw
      .where((a) => a.id.isNotEmpty && (a.platform == 'apple' || session.bindings[a.platform ?? '']?.bound == true))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text('新发行', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          if (_plats.isNotEmpty) ...[
            ChipBar(
              items: [('all', '全部'), ..._plats.map((p) => (p, MX.label(p)))],
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
            const SizedBox(height: 14),
          ],
          if (_shown.isEmpty && !_loading)
            _emptyState(Icons.album, '暂无新发行')
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.78,
              crossAxisSpacing: 16,
              mainAxisSpacing: 18,
              children: [
                for (final item in _shown)
                  CatalogTile(
                    cover: item.cover,
                    title: item.title ?? '',
                    subtitle: item.source ?? '',
                    platform: item.platform,
                    route: AlbumRoute(platform: item.platform ?? '', id: item.id),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FavoritesView — 收藏 (segmented, with select-to-unfavorite)
// ---------------------------------------------------------------------------

class FavoritesView extends StatefulWidget {
  const FavoritesView({super.key});
  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView> {
  String _tab = 'track';
  List<Track> _tracks = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  List<Playlist> _playlists = [];
  String? _favId;
  bool _loading = true;

  int get _count {
    switch (_tab) {
      case 'album':
        return _albums.length;
      case 'artist':
        return _artists.length;
      case 'playlist':
        return _playlists.length;
      default:
        return _tracks.length;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    setState(() => _loading = _tracks.isEmpty);
    var mine = session.peekPage('library.recent.mine', PlaylistsPayload.fromJson);
    final box = await session.fetchPage('/api/my/playlists', cacheKey: 'library.recent.mine', factory: PlaylistsPayload.fromJson);
    if (box != null) mine = box;
    for (final p in mine?.playlists ?? []) {
      if (p.kind == 'favorites') {
        _favId = p.id;
        break;
      }
    }
    final id = _favId;
    if (id != null) {
      final cached = session.peekPage('library.browse.songs', PlaylistBox.fromJson);
      if (_tracks.isEmpty && cached != null) _tracks = cached.playlist?.tracks ?? [];
      final row = await session.fetchPage('/api/my/playlists/$id', cacheKey: 'library.browse.songs', factory: PlaylistBox.fromJson);
      if (row != null) _tracks = row.playlist?.tracks ?? [];
    }
    await _loadKind();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadKind() async {
    final session = context.read<SessionStore>();
    switch (_tab) {
      case 'album':
        final cached = session.peekPage('library.browse.albums', (m) => ItemsBox.fromJson(m, Album.fromJson));
        if (_albums.isEmpty && cached != null) _albums = cached.items ?? [];
        final box = await session.fetchPage('/api/my/favorites/items?kind=album',
            cacheKey: 'library.browse.albums', factory: (m) => ItemsBox.fromJson(m, Album.fromJson));
        if (box != null) _albums = box.items ?? [];
        break;
      case 'artist':
        final cached = session.peekPage('library.browse.artists', (m) => ItemsBox.fromJson(m, Artist.fromJson));
        if (_artists.isEmpty && cached != null) _artists = cached.items ?? [];
        final box = await session.fetchPage('/api/my/favorites/items?kind=artist',
            cacheKey: 'library.browse.artists', factory: (m) => ItemsBox.fromJson(m, Artist.fromJson));
        if (box != null) _artists = box.items ?? [];
        break;
      case 'playlist':
        final cached = session.peekPage('library.browse.favPlaylists', (m) => ItemsBox.fromJson(m, Playlist.fromJson));
        if (_playlists.isEmpty && cached != null) _playlists = cached.items ?? [];
        final box = await session.fetchPage('/api/my/favorites/items?kind=playlist',
            cacheKey: 'library.browse.favPlaylists', factory: (m) => ItemsBox.fromJson(m, Playlist.fromJson));
        if (box != null) _playlists = box.items ?? [];
        break;
    }
    if (mounted) setState(() {});
  }

  AppRoute _playlistRoute(Playlist p) {
    final plat = p.platform ?? 'local';
    final kind = plat == 'local' || p.listKind == 'mine'
        ? ListKind.mine
        : (p.listKind == 'chart' ? ListKind.chart : ListKind.platform);
    return PlaylistRoute(platform: plat, id: p.id, kind: kind, fromLibrary: true);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    final ui = context.read<UIStore>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text('收藏', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
        actions: [
          if (_tab == 'track' && _tracks.isNotEmpty)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, color: MX.fg),
              color: MX.panel,
              onSelected: (v) {
                if (v == 'organize') ui.openOrganization(_tracks);
                if (v == 'play') player.replaceQueue(_tracks, start: 0);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'organize', child: Text('整理音源', style: TextStyle(color: MX.fg))),
                PopupMenuItem(value: 'play', child: Text('播放', style: TextStyle(color: MX.fg))),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentBar(
              items: const [('track', '歌曲'), ('album', '专辑'), ('artist', '艺人'), ('playlist', '歌单')],
              selected: _tab,
              onChanged: (v) {
                if (v == _tab) return;
                setState(() => _tab = v);
                _loadKind();
              },
            ),
          ),
          Expanded(
            child: _loading && _count == 0
                ? Center(child: CircularProgressIndicator(color: MX.ember))
                : _content(ui),
          ),
        ],
      ),
    );
  }

  Widget _content(UIStore ui) {
    switch (_tab) {
      case 'album':
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
              16, 4, 16, MediaQuery.paddingOf(context).bottom),
          itemCount: _albums.length,
          itemBuilder: (_, i) {
            final a = _albums[i];
            return CatalogListRow(
                cover: a.cover, title: a.displayTitle, subtitle: a.artistText, platform: a.platform,
                route: AlbumRoute(platform: a.platform, id: a.id));
          },
        );
      case 'artist':
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
              16, 4, 16, MediaQuery.paddingOf(context).bottom),
          itemCount: _artists.length,
          itemBuilder: (_, i) {
            final a = _artists[i];
            return CatalogListRow(
                cover: a.cover, title: a.displayName, subtitle: '艺人', platform: a.platform, circle: true,
                route: ArtistRoute(platform: a.platform, id: a.id));
          },
        );
      case 'playlist':
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
              16, 4, 16, MediaQuery.paddingOf(context).bottom),
          itemCount: _playlists.length,
          itemBuilder: (_, i) {
            final p = _playlists[i];
            return CatalogListRow(
                cover: p.cover, mosaic: p.artTiles, title: p.displayTitle,
                subtitle: '${p.trackCount ?? 0} 首', platform: p.platform, route: _playlistRoute(p));
          },
        );
      default:
        if (_tracks.isEmpty) return _emptyState(Icons.favorite_border, '还没有收藏歌曲');
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
              16, 4, 16, MediaQuery.paddingOf(context).bottom),
          itemCount: _tracks.length,
          itemBuilder: (_, i) => TrackRow(track: _tracks[i], index: i, queue: _tracks),
        );
    }
  }
}

// ---------------------------------------------------------------------------

Widget _emptyState(IconData icon, String title) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 52),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: MX.dim, size: 44),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
