import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  bool failed;
  DateTime? loadedAt;
  _ShelfState(this.row, {this.loading = true, this.failed = false, this.loadedAt});
}

class _HomeViewState extends State<HomeView> {
  static const _kinds = [
    ('daily', 'hero'),
    ('taste', 'tracks'),
    ('guess', 'tracks'),
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
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    for (final (id, layout) in _kinds) {
      final cached = context.read<SessionStore>().local.homeRaw(id);
      final row = cached != null
          ? _rowFromRaw(id, layout, cached)
          : ShelfRow(id: id, layout: layout);
      _shelves[id] = _ShelfState(row, loading: row.empty, loadedAt: cached != null ? DateTime.now() : null);
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
      tracks: (data.tracks ?? const []).where((t) => t.title.isNotEmpty).toList(),
      sections: data.sections ?? const [],
    );
  }

  Future<void> _loadAll() async {
    final gen = _generation;
    final session = context.read<SessionStore>();
    // Resolve the behavior-driven daily mix (kind == 'auto').
    final box = await session.fetchPage('/api/my/playlists',
        cacheKey: 'library.recent.mine', factory: PlaylistsPayload.fromJson);
    if (mounted && gen == _generation) {
      Playlist? mix;
      for (final p in box?.playlists ?? const <Playlist>[]) {
        if (p.kind == 'auto') {
          mix = p;
          break;
        }
      }
      if (mix != null) setState(() => _dailyMix = mix);
    }
    for (final (id, layout) in _kinds) {
      if (gen != _generation) return;
      await _loadShelf(id, layout, gen);
    }
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
        final raw = await session.api.getRawBody('/api/home/$id');
        if (!mounted || gen != _generation) return;
        final data = APIClient.decodeCached(raw, HomeShelf.fromJson);
        final row = _rowFromShelf(id, layout, data) ?? ShelfRow(id: id, layout: layout);
        if (data?.refreshing == true) {
          if (!row.empty) setState(() => _shelves[id] = _ShelfState(row, loading: true, loadedAt: null));
          final delayMs = (data?.retryAfterMs ?? 1000).clamp(300, 12000).toInt();
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
        setState(() => _shelves[id] = _ShelfState(row, loading: false, loadedAt: DateTime.now()));
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
      color: MX.ink,
      child: RefreshIndicator(
        color: MX.ember,
        backgroundColor: MX.panel,
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text('主页',
                        style: TextStyle(color: MX.fg, fontSize: 32, fontWeight: FontWeight.bold)),
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
    return [
      _ShelfSection(state: st),
      if (id == 'daily' && _dailyMix != null) _dailyMixEntry(_dailyMix!),
      if (id == 'guess') _RecentShelf(generation: _generation),
    ];
  }

  Widget _dailyMixEntry(Playlist mix) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.read<UIStore>().open(
            PlaylistRoute(platform: 'local', id: mix.id, kind: ListKind.mine, fromLibrary: false)),
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
                              style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: MX.ember, borderRadius: BorderRadius.circular(999)),
                          child: const Text('为你',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
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
        decoration: BoxDecoration(color: MX.fillSoft, borderRadius: BorderRadius.circular(12)),
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
                      style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('绑定音乐平台，发现专属歌单和每日推荐。',
                      style: TextStyle(color: MX.dim, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => context.read<UIStore>().open(SimpleRoute.settings),
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

/// Route for a home feed item — mirrors Swift `homeRoute`.
AppRoute homeRoute(FeedItem item) {
  final platform = item.platform ?? '';
  if (item.type == 'chart' && (item.chartId ?? '').isNotEmpty) {
    return PlaylistRoute(platform: platform, id: item.chartId!, kind: ListKind.chart, fromLibrary: false);
  }
  if (item.type == 'album') return AlbumRoute(platform: platform, id: item.id);
  if (item.type == 'artist') return ArtistRoute(platform: platform, id: item.id);
  return PlaylistRoute(platform: platform, id: item.id, kind: ListKind.platform, fromLibrary: false);
}

/// One home shelf. Mirrors Swift `ShelfSection`.
class _ShelfSection extends StatelessWidget {
  final _ShelfState state;
  const _ShelfSection({required this.state});

  ShelfRow get row => state.row;

  @override
  Widget build(BuildContext context) {
    if (!state.loading && row.empty) return const SizedBox.shrink();
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
                        style: TextStyle(color: MX.fg, fontSize: 20, fontWeight: FontWeight.bold)),
                    if (row.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(row.subtitle, style: TextStyle(color: MX.dim, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (state.loading && row.empty)
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
              SkeletonBar(width: hero ? 220 : 150, height: hero ? 260 : 150, corner: 12),
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
    if (items.isEmpty) return const SizedBox.shrink();
    final hero = row.layout == 'hero';
    final width = hero ? 260.0 : row.layout == 'artists' ? 150.0 : 160.0;
    return SizedBox(
      height: hero ? width * 1.32 + 4 : width + 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, i) => _HomeCard(item: items[i], shelfId: row.id, layout: row.layout, width: width),
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
  const _HomeCard({required this.item, required this.shelfId, required this.layout, required this.width});

  String get _subtitle {
    final artists = {for (final t in item.tracks ?? const <Track>[]) ...t.artists}.toList()..sort();
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
          crossAxisAlignment: artists ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            CoverArt(src: item.cover, size: width, corner: artists ? width / 2 : 9, circle: artists),
            const SizedBox(height: 8),
            Text(item.title ?? '未命名推荐',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: artists ? TextAlign.center : TextAlign.start,
                style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
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
                    colors: [Colors.transparent, Colors.black26, Colors.black87],
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
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(item.title ?? '专属精选',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withOpacity(0.84), fontSize: 12)),
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
    final colWidth = (MediaQuery.of(context).size.width - 40).clamp(250.0, 360.0);
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
                      style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
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
      _tracks = (cached.items ?? const []).take(12).map((t) => t..historyReplay = true).toList();
    }
    if (mounted) setState(() => _loading = _tracks.isEmpty);
    final result = await session.fetchPage('/api/me/history?kind=track&limit=80',
        cacheKey: 'recents.track', factory: HistoryPayload.fromJson);
    if (!mounted) return;
    setState(() {
      if (result != null) {
        _tracks = (result.items ?? const []).take(12).map((t) => t..historyReplay = true).toList();
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
                  style: TextStyle(color: MX.fg, fontSize: 17, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.chevron_right, color: MX.dim),
                onPressed: () => context.read<UIStore>().open(const SimpleRoute('recents')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: tile + 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _loading && _tracks.isEmpty ? 4 : _tracks.take(6).length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (_, i) {
                if (_loading && _tracks.isEmpty) {
                  return const SizedBox(width: tile, child: SkeletonBar(width: tile, height: tile, corner: 8));
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
                            style: TextStyle(color: MX.fg, fontSize: 12, fontWeight: FontWeight.w500)),
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

  bool get empty => items.isEmpty && tracks.isEmpty && sections.every((s) => s.items.isEmpty);

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
