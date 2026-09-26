import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';

/// Home / recommendations feed. Mirrors Swift `HomeView`: a vertical stack of
/// horizontally-scrolling shelves (每日私享 hero, song rails, playlist/album/
/// artist rails, charts) loaded lazily from `/api/home/<id>`.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _ShelfState {
  ShelfRow row;
  bool loading;
  bool failed = false;
  DateTime? loadedAt;
  _ShelfState(this.row, {this.loading = true, this.loadedAt});
}

class _HomeViewState extends State<HomeView> {
  static const _kinds = [
    ('daily', 'hero'),
    ('taste', 'tracks'),
    ('guess', 'guess'),
    ('playlists', 'playlists'),
    ('albums', 'albums'),
    ('artists', 'artists'),
    ('radar', 'playlists'),
    ('newsongs', 'tracks'),
    ('charts', 'charts'),
    ('following', 'tracks'),
    ('vip', 'tracks'),
  ];

  final Map<String, _ShelfState> _shelves = {};
  Playlist? _dailyMix;
  List<Track> _preferenceTracks = [];
  bool _preferenceTracksLoading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    for (final (id, layout) in _kinds) {
      final cached = context.read<SessionStore>().local.homeRaw(id);
      final row = cached != null
          ? _rowFromRaw(id, layout, cached)
          : ShelfRow(id: id, layout: layout);
      _shelves[id] = _ShelfState(row,
          loading: row.empty, loadedAt: cached != null ? DateTime.now() : null);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  ShelfRow _rowFromRaw(String id, String layout, String raw) {
    final shelf = APIClient.decodeCached(raw, HomeShelf.fromJson);
    return _rowFromShelf(id, layout, shelf) ?? ShelfRow(id: id, layout: layout);
  }

  ShelfRow? _rowFromShelf(String id, String layout, HomeShelf? data) {
    if (data == null) return null;
    return ShelfRow(
      id: id,
      layout: layout,
      title: data.title ?? '',
      more: data.more,
      items: data.items ?? const [],
      tracks:
          (data.tracks ?? const []).where((t) => t.title.isNotEmpty).toList(),
      sections: data.sections ?? const [],
    );
  }

  Future<void> _loadAll() async {
    final gen = _generation;
    final session = context.read<SessionStore>();
    // Resolve the behavior-driven daily mix and the local favorites playlist.
    final box = await session.fetchPage('/api/my/playlists',
        cacheKey: 'library.recent.mine', factory: PlaylistsPayload.fromJson);
    Playlist? favorites;
    if (mounted && gen == _generation) {
      Playlist? mix;
      for (final p in box?.playlists ?? const <Playlist>[]) {
        if (p.kind == 'auto') {
          mix = p;
        } else if (p.kind == 'favorites') {
          favorites = p;
        }
      }
      if (mix != null) setState(() => _dailyMix = mix);
    }
    final preferenceLoad = _loadPreferenceTracks(session, favorites, gen);
    for (final (id, layout) in _kinds) {
      if (gen != _generation) return;
      await _loadShelf(id, layout, gen);
    }
    await preferenceLoad;
  }

  Future<void> _loadPreferenceTracks(
      SessionStore session, Playlist? localFavorites, int gen) async {
    final collected = <Track>[];

    void addTracks(Iterable<Track> tracks) {
      collected.addAll(tracks.where((track) => track.title.isNotEmpty));
    }

    void publish({bool loading = true}) {
      if (!mounted || gen != _generation) return;
      final seen = <String>{};
      final merged = <Track>[
        ...collected,
        ..._preferenceTracks,
      ].where((track) => seen.add(track.key)).take(200).toList();
      setState(() {
        _preferenceTracks = merged;
        _preferenceTracksLoading = loading;
      });
    }

    try {
      if (localFavorites != null) {
        addTracks(localFavorites.tracks ?? const <Track>[]);
        final cacheKey = 'home.guess.favorites.v2.${localFavorites.id}';
        final cached = session.peekPage(cacheKey, PlaylistBox.fromJson);
        addTracks(cached?.playlist?.tracks ?? const <Track>[]);
        publish();

        final favoriteBox = await session.fetchPage(
          '/api/my/playlists/${Uri.encodeComponent(localFavorites.id)}?limit=200',
          cacheKey: cacheKey,
          factory: PlaylistBox.fromJson,
        );
        addTracks(favoriteBox?.playlist?.tracks ?? const <Track>[]);
        publish();
      }

      var libraries =
          session.peekPage('library.browse.lib', LibraryPayload.fromJson);
      final fetchedLibraries = await session.fetchPage(
          '/api/me/libraries/playlists',
          cacheKey: 'library.browse.lib',
          factory: LibraryPayload.fromJson);
      libraries = fetchedLibraries ?? libraries;

      final preferencePlaylists = <String, (String, Playlist)>{};
      for (final entry
          in (libraries?.groups ?? const <String, List<Playlist>>{}).entries) {
        for (final playlist in entry.value) {
          if (!_isLikedPlaylist(playlist)) continue;
          final platform = playlist.platform ?? entry.key;
          preferencePlaylists['$platform::${playlist.id}'] =
              (platform, playlist);
          addTracks(playlist.tracks ?? const <Track>[]);
        }
      }

      var savedPlaylists = session.peekPage('home.guess.savedPlaylists',
          (data) => ItemsBox.fromJson(data, Playlist.fromJson));
      final fetchedSavedPlaylists = await session.fetchPage(
          '/api/my/favorites/items?kind=playlist',
          cacheKey: 'home.guess.savedPlaylists',
          factory: (data) => ItemsBox.fromJson(data, Playlist.fromJson));
      savedPlaylists = fetchedSavedPlaylists ?? savedPlaylists;
      for (final playlist in savedPlaylists?.items ?? const <Playlist>[]) {
        final platform = playlist.platform ?? '';
        if (platform.isEmpty || platform == 'local') continue;
        preferencePlaylists['$platform::${playlist.id}'] = (platform, playlist);
        addTracks(playlist.tracks ?? const <Track>[]);
      }
      publish();

      final details =
          await Future.wait(preferencePlaylists.values.take(8).map((entry) {
        final platform = entry.$1;
        final playlist = entry.$2;
        final id = Uri.encodeComponent(playlist.id);
        return session.fetchPage(
          '/api/playlists/$platform/$id?limit=200',
          cacheKey: 'home.guess.liked.$platform.${playlist.id}',
          factory: Playlist.fromJson,
        );
      }));
      for (final playlist in details) {
        addTracks(playlist?.tracks ?? const <Track>[]);
      }
    } finally {
      publish(loading: false);
    }
  }

  bool _isLikedPlaylist(Playlist playlist) {
    final kind =
        '${playlist.kind ?? ''} ${playlist.listKind ?? ''}'.toLowerCase();
    if (playlist.id.toLowerCase() == 'liked' ||
        kind.contains('liked') ||
        kind.contains('favorite')) {
      return true;
    }
    final title =
        '${playlist.name ?? ''} ${playlist.title ?? ''}'.toLowerCase();
    return title.contains('我喜欢') ||
        title.contains('喜欢的') ||
        title.contains('收藏的歌曲') ||
        title.contains('红心') ||
        title.contains('liked songs') ||
        title.contains('favorites');
  }

  Iterable<Track> _tracksIn(_ShelfState? state) sync* {
    final row = state?.row;
    if (row == null) return;
    yield* row.tracks;
    for (final item in row.items) {
      yield* item.tracks ?? const <Track>[];
    }
    for (final section in row.sections) {
      for (final item in section.items) {
        yield* item.tracks ?? const <Track>[];
      }
    }
  }

  List<Track> get _guessTracks {
    final seen = <String>{};
    return <Track>[
      ..._tracksIn(_shelves['guess']),
      ..._preferenceTracks,
      ..._tracksIn(_shelves['taste']),
      ..._tracksIn(_shelves['daily']),
    ]
        .where((track) => track.title.isNotEmpty && seen.add(track.key))
        .take(200)
        .toList();
  }

  Future<void> _loadShelf(String id, String layout, int gen) async {
    final st = _shelves[id];
    if (st != null && st.loadedAt != null && !st.failed) {
      final fresh = DateTime.now().difference(st.loadedAt!).inSeconds < 45;
      if (fresh) return;
    }
    final session = context.read<SessionStore>();
    try {
      // Retry loop for server-side "refreshing" responses.
      for (var attempt = 0; attempt < 4; attempt++) {
        final path =
            id == 'guess' ? '/api/home/$id?limit=200' : '/api/home/$id';
        final raw = await session.api.getRawBody(path);
        if (!mounted || gen != _generation) return;
        final data = APIClient.decodeCached(raw, HomeShelf.fromJson);
        final row =
            _rowFromShelf(id, layout, data) ?? ShelfRow(id: id, layout: layout);
        if (data?.refreshing == true) {
          if (!row.empty)
            setState(() =>
                _shelves[id] = _ShelfState(row, loading: true, loadedAt: null));
          final delayMs =
              (data?.retryAfterMs ?? 1000).clamp(300, 12000).toInt();
          if (attempt >= 3 || delayMs >= 12000) {
            setState(() {
              _shelves[id]!.loading = false;
              _shelves[id]!.failed = true;
            });
            return;
          }
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        setState(() => _shelves[id] =
            _ShelfState(row, loading: false, loadedAt: DateTime.now()));
        session.local.saveHomeRaw(id, raw);
        return;
      }
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _shelves[id]?.loading = false;
        _shelves[id]?.failed = true;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _generation++;
      _preferenceTracksLoading = true;
      for (final st in _shelves.values) {
        st.loadedAt = null;
        st.failed = false;
      }
    });
    await _loadAll();
  }

  bool get _anyFailed => _shelves.values.any((s) => s.failed);
  bool get _noBindings =>
      !context.read<SessionStore>().bindings.values.any((b) => b.bound == true);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: RefreshIndicator(
        color: MX.ember,
        backgroundColor: MX.panel,
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, MediaQuery.paddingOf(context).bottom),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text('主页',
                        style: TextStyle(
                            color: MX.fg,
                            fontSize: 32,
                            fontWeight: FontWeight.bold)),
                  ),
                  if (_noBindings) _bindHint(),
                  if (_anyFailed) _refreshNotice(),
                  for (final (id, _) in _kinds) ..._shelfBlock(id),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _shelfBlock(String id) {
    final st = _shelves[id];
    if (st == null) return const [];
    if (id == 'guess') {
      return [_RecentShelf(generation: _generation)];
    }
    return [
      _ShelfSection(
        state: st,
        guessTracks: id == 'daily' ? _guessTracks : const [],
        guessLoading: id == 'daily' &&
            ((_shelves['guess']?.loading ?? true) || _preferenceTracksLoading),
      ),
      if (id == 'daily' && _dailyMix != null) _dailyMixEntry(_dailyMix!),
    ];
  }

  Widget _dailyMixEntry(Playlist mix) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.read<UIStore>().open(PlaylistRoute(
            platform: 'local',
            id: mix.id,
            kind: ListKind.mine,
            fromLibrary: false)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MX.ember.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MX.ember.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: MX.ember, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(mix.name ?? '每日私享',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: MX.fg,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: MX.ember,
                              borderRadius: BorderRadius.circular(999)),
                          child: Text('为你',
                              style: TextStyle(
                                  color: MX.onAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('根据你的收听生成 · 每日更新',
                        style: TextStyle(color: MX.dim, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: MX.dim, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bindHint() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: MX.fillSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(Icons.person_add_alt, color: MX.dim, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('让推荐更懂你',
                      style: TextStyle(
                          color: MX.fg,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('绑定音乐平台，发现专属歌单和每日推荐。',
                      style: TextStyle(color: MX.dim, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () =>
                  context.read<UIStore>().open(SimpleRoute.settings),
              child: const Text('去设置'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refreshNotice() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: MX.dim, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('部分推荐仍在更新或暂时不可用，稍后可重试。',
                style: TextStyle(color: MX.dim, fontSize: 12)),
          ),
          OutlinedButton(onPressed: _refresh, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _GuessPlaylistCard extends StatelessWidget {
  final List<Track> tracks;
  final double width;
  final double height;
  const _GuessPlaylistCard({
    required this.tracks,
    required this.width,
    required this.height,
  });

  void _play(BuildContext context) {
    if (tracks.isEmpty) return;
    final player = context.read<PlayerStore>();
    if (!player.shuffle) player.toggleShuffle();
    final start = DateTime.now().microsecondsSinceEpoch % tracks.length;
    player.replaceQueue(tracks, start: start);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _play(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CoverArt(
                src: tracks.first.cover,
                mosaic: tracks
                    .map((track) => track.cover ?? '')
                    .where((cover) => cover.isNotEmpty)
                    .take(9)
                    .toList(),
                size: width,
                height: height,
                corner: 14,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.42, 1],
                    colors: [Colors.black12, Colors.black38, Colors.black87],
                  ),
                ),
              ),
              const Positioned(top: 16, left: 16, child: _GuessBadge()),
              Positioned(
                right: 18,
                bottom: 18,
                child: _GuessPlayButton(onPressed: () => _play(context)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 82, 18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('猜你喜欢',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('根据你的收藏与喜欢生成 · ${tracks.length} 首歌曲',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            fontSize: 13)),
                    const SizedBox(height: 3),
                    Text('全平台 · 随机播放',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.68),
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuessBadge extends StatelessWidget {
  const _GuessBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: MX.ember,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, size: 15, color: MX.onAccent),
          const SizedBox(width: 4),
          Text('猜你喜欢',
              style: TextStyle(
                  color: MX.onAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _GuessPlayButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _GuessPlayButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MX.ember,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: '播放',
        onPressed: onPressed,
        icon: Icon(Icons.play_arrow_rounded, color: MX.onAccent, size: 31),
        iconSize: 31,
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}

/// Route for a home feed item — mirrors Swift `homeRoute`.
AppRoute homeRoute(FeedItem item) {
  final platform = item.platform ?? '';
  if (item.type == 'chart' && (item.chartId ?? '').isNotEmpty) {
    return PlaylistRoute(
        platform: platform,
        id: item.chartId!,
        kind: ListKind.chart,
        fromLibrary: false);
  }
  if (item.type == 'album') return AlbumRoute(platform: platform, id: item.id);
  if (item.type == 'artist')
    return ArtistRoute(platform: platform, id: item.id);
  return PlaylistRoute(
      platform: platform,
      id: item.id,
      kind: ListKind.platform,
      fromLibrary: false);
}

/// One home shelf. Mirrors Swift `ShelfSection`.
class _ShelfSection extends StatelessWidget {
  final _ShelfState state;
  final List<Track> guessTracks;
  final bool guessLoading;
  const _ShelfSection({
    required this.state,
    this.guessTracks = const [],
    this.guessLoading = false,
  });

  ShelfRow get row => state.row;
  bool get _hasGuessCard =>
      row.id == 'daily' && (guessTracks.isNotEmpty || guessLoading);

  @override
  Widget build(BuildContext context) {
    if (!state.loading && row.empty && !_hasGuessCard) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.displayTitle,
                        style: TextStyle(
                            color: MX.fg,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    if (row.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(row.subtitle,
                          style: TextStyle(color: MX.dim, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (state.loading && row.empty && !_hasGuessCard)
            _skeleton()
          else if (row.layout == 'tracks')
            _songShelf(context)
          else
            _rail(context),
        ],
      ),
    );
  }

  Widget _skeleton() {
    final hero = row.layout == 'hero';
    return SizedBox(
      height: hero ? 300 : 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, __) => SizedBox(
          width: hero ? 220 : 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBar(
                  width: hero ? 220 : 150,
                  height: hero ? 260 : 150,
                  corner: 12),
              const SizedBox(height: 8),
              const SkeletonBar(width: 110, height: 13),
            ],
          ),
        ),
      ),
    );
  }

  Widget _songShelf(BuildContext context) {
    if (row.tracks.isEmpty && row.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (row.tracks.isNotEmpty) _HomeSongShelf(tracks: row.tracks),
        if (row.items.isNotEmpty) ...[
          const SizedBox(height: 16),
          _rail(context),
        ],
      ],
    );
  }

  Widget _rail(BuildContext context) {
    final items = _uniqueItems(row.items);
    if (items.isEmpty && !_hasGuessCard) return const SizedBox.shrink();
    final hero = row.layout == 'hero';
    final width = hero
        ? 260.0
        : row.layout == 'artists'
            ? 150.0
            : 160.0;
    final height = hero ? width * 1.32 : width + 78;
    return SizedBox(
      height: height + (hero ? 4 : 0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length + (_hasGuessCard ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, i) {
          if (_hasGuessCard && i == 0) {
            if (guessTracks.isEmpty) {
              return SkeletonBar(width: width, height: height, corner: 12);
            }
            return _GuessPlaylistCard(
                tracks: guessTracks, width: width, height: height);
          }
          final itemIndex = i - (_hasGuessCard ? 1 : 0);
          return _HomeCard(
              item: items[itemIndex],
              shelfId: row.id,
              layout: row.layout,
              width: width);
        },
      ),
    );
  }

  static List<FeedItem> _uniqueItems(List<FeedItem> items) {
    final seen = <String>{};
    final out = <FeedItem>[];
    for (final item in items) {
      final identity = '${item.platform ?? ''}::${item.type ?? ''}::${item.id}';
      if (seen.add(identity)) out.add(item);
    }
    return out;
  }
}

/// A feed card in a horizontal rail. Mirrors Swift `HomeRecommendationCard`.
class _HomeCard extends StatelessWidget {
  final FeedItem item;
  final String shelfId;
  final String layout;
  final double width;
  const _HomeCard(
      {required this.item,
      required this.shelfId,
      required this.layout,
      required this.width});

  String get _subtitle {
    final artists = {
      for (final t in item.tracks ?? const <Track>[]) ...t.artists
    }.toList()
      ..sort();
    if (artists.isNotEmpty) return artists.take(3).join('、');
    if ((item.source ?? '').isNotEmpty) return item.source!;
    return MX.label(item.platform);
  }

  String get _kindLabel {
    switch (item.type) {
      case 'album':
        return '专辑推荐';
      case 'artist':
        return '艺人精选';
      case 'chart':
        return '热门榜单';
      case 'daily':
        return '每日推荐';
      default:
        return shelfId == 'daily' ? '专属推荐' : '精选歌单';
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = homeRoute(item);
    if (layout == 'hero') return _poster(context, route);
    final artists = layout == 'artists';
    return InkWell(
      onTap: () => context.read<UIStore>().open(route),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment:
              artists ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            CoverArt(
                src: item.cover,
                size: width,
                corner: artists ? width / 2 : 9,
                circle: artists),
            const SizedBox(height: 8),
            Text(item.title ?? '未命名推荐',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: artists ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                    color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(artists ? '艺人 · ${MX.label(item.platform)}' : _subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: artists ? TextAlign.center : TextAlign.start,
                style: TextStyle(color: MX.dim, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _poster(BuildContext context, AppRoute route) {
    final h = width * 1.32;
    return InkWell(
      onTap: () => context.read<UIStore>().open(route),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CoverArt(src: item.cover, size: width, height: h, corner: 12),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black26,
                      Colors.black87
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_kindLabel,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(item.title ?? '专属精选',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.84),
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grouped 3-per-column song rail. Mirrors Swift `HomeSongShelf`.
class _HomeSongShelf extends StatelessWidget {
  final List<Track> tracks;
  const _HomeSongShelf({required this.tracks});

  @override
  Widget build(BuildContext context) {
    final preview = tracks.take(18).toList();
    final groups = <List<Track>>[];
    for (var i = 0; i < preview.length; i += 3) {
      groups.add(preview.sublist(i, (i + 3).clamp(0, preview.length)));
    }
    final colWidth =
        (MediaQuery.of(context).size.width - 40).clamp(250.0, 360.0);
    return SizedBox(
      height: 3 * 68.0,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 24),
        itemBuilder: (_, gi) => SizedBox(
          width: colWidth,
          child: Column(
            children: [
              for (final track in groups[gi])
                _HomeSongRow(track: track, queue: tracks),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSongRow extends StatelessWidget {
  final Track track;
  final List<Track> queue;
  const _HomeSongRow({required this.track, required this.queue});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    return InkWell(
      onTap: () {
        final start = queue.indexWhere((t) => t.key == track.key);
        player.replaceQueue(queue, start: start < 0 ? 0 : start);
      },
      onLongPress: () => showTrackActions(context, track),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CoverArt(src: track.cover, size: 48, corner: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: MX.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(track.artistText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MX.dim, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.more_horiz, color: MX.mute),
              onPressed: () => showTrackActions(context, track),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "最近播放" glimpse. Mirrors Swift `HomeRecentShelf`.
class _RecentShelf extends StatefulWidget {
  final int generation;
  const _RecentShelf({required this.generation});
  @override
  State<_RecentShelf> createState() => _RecentShelfState();
}

class _RecentShelfState extends State<_RecentShelf> {
  List<Track> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant _RecentShelf old) {
    super.didUpdateWidget(old);
    if (old.generation != widget.generation) _load();
  }

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    final cached = session.peekPage('recents.track', HistoryPayload.fromJson);
    if (cached != null && _tracks.isEmpty) {
      _tracks = (cached.items ?? const [])
          .take(12)
          .map((t) => t..historyReplay = true)
          .toList();
    }
    if (mounted) setState(() => _loading = _tracks.isEmpty);
    final result = await session.fetchPage(
        '/api/me/history?kind=track&limit=80',
        cacheKey: 'recents.track',
        factory: HistoryPayload.fromJson);
    if (!mounted) return;
    setState(() {
      if (result != null) {
        _tracks = (result.items ?? const [])
            .take(12)
            .map((t) => t..historyReplay = true)
            .toList();
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _tracks.isEmpty) return const SizedBox.shrink();
    final player = context.read<PlayerStore>();
    const tile = 120.0;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('最近播放',
                  style: TextStyle(
                      color: MX.fg, fontSize: 17, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.chevron_right, color: MX.dim),
                onPressed: () =>
                    context.read<UIStore>().open(const SimpleRoute('recents')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: tile + 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount:
                  _loading && _tracks.isEmpty ? 4 : _tracks.take(6).length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (_, i) {
                if (_loading && _tracks.isEmpty) {
                  return const SizedBox(
                      width: tile,
                      child: SkeletonBar(width: tile, height: tile, corner: 8));
                }
                final track = _tracks[i];
                return InkWell(
                  onTap: () => player.replaceQueue(_tracks, start: i),
                  child: SizedBox(
                    width: tile,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CoverArt(src: track.cover, size: tile, corner: 8),
                        const SizedBox(height: 7),
                        Text(track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: MX.fg,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                        Text(track.artistText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: MX.dim, fontSize: 11)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Home shelf view-model. Mirrors Swift `ShelfRow` (display title / subtitle).
class ShelfRow {
  final String id;
  final String layout;
  final String title;
  final String? more;
  final List<FeedItem> items;
  final List<Track> tracks;
  final List<HomeShelfSection> sections;

  ShelfRow({
    required this.id,
    required this.layout,
    this.title = '',
    this.more,
    this.items = const [],
    this.tracks = const [],
    this.sections = const [],
  });

  bool get empty =>
      items.isEmpty && tracks.isEmpty && sections.every((s) => s.items.isEmpty);

  String get displayTitle {
    if (id == 'daily') return '专属精选推荐';
    if (title.isNotEmpty) return title;
    switch (id) {
      case 'taste':
        return '为你推荐歌曲';
      case 'guess':
        return '猜你喜欢';
      case 'playlists':
        return '精选歌单';
      case 'albums':
        return '值得一听的新专辑';
      case 'artists':
        return '发现更多艺人';
      case 'radar':
        return '探索新声音';
      case 'newsongs':
        return '新歌速递';
      case 'charts':
        return '热门榜单';
      case 'fans':
        return '与你同频';
      case 'following':
        return '关注艺人的新动态';
      case 'vip':
        return '精选好歌';
      default:
        return '为你推荐';
    }
  }

  String get subtitle {
    switch (id) {
      case 'daily':
        return '从熟悉的旋律，到下一首心动。';
      case 'taste':
        return '从这些歌曲开始今天的聆听。';
      case 'guess':
        return '来自已绑定音乐平台的个性化推荐。';
      case 'playlists':
        return '为不同的心情，找到合适的歌单。';
      case 'albums':
        return '留些时间，听一张完整专辑。';
      case 'artists':
        return '认识新的声音，重温熟悉的作品。';
      default:
        return '';
    }
  }
}
