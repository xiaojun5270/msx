import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/search_store.dart';
import '../stores/ui_store.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';

/// The pushed platform/share search results page. Mirrors Swift
/// `SearchResultsPage`: type tab capsules, a "最佳结果" top card, grouped
/// sections, and pagination.
class SearchResultsView extends StatefulWidget {
  const SearchResultsView({super.key});

  @override
  State<SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends State<SearchResultsView> {
  String _tab = 'all';

  Color get _tone {
    final store = context.read<SearchStore>();
    switch (store.mode) {
      case SearchMode.suggestions:
        return MX.mute;
      case SearchMode.platform:
        final t = store.platformTarget;
        return MX.tone(t?.kind == 'source' ? 'source' : t?.platform);
      case SearchMode.share:
        return context.read<UIStore>().themeAccent.color;
    }
  }

  String get _remoteTitle {
    final store = context.read<SearchStore>();
    switch (store.mode) {
      case SearchMode.suggestions:
        return '本地资料';
      case SearchMode.platform:
        return store.platformTarget?.name ?? '';
      case SearchMode.share:
        return '分享链接';
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SearchStore>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(store.query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: MX.fg, fontSize: 17, fontWeight: FontWeight.bold)),
            Text(_remoteTitle, style: TextStyle(color: MX.dim, fontSize: 12)),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: MX.ember,
        backgroundColor: MX.panel,
        onRefresh: () async => store.retryRemote(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.paddingOf(context).bottom),
          children: [
            _tabCapsules(store),
            const SizedBox(height: 14),
            ..._status(store),
            if (store.remoteResult != null)
              ..._resultContent(store, store.remoteResult!)
            else if (!store.remoteLoading && store.remoteError == null)
              _paused(store),
            if (store.canLoadMore && _tab != 'all') ...[
              const SizedBox(height: 16),
              Center(
                child: FilledButton.icon(
                  onPressed: store.loadMore,
                  style: FilledButton.styleFrom(backgroundColor: _tone),
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  label: const Text('加载更多结果'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tabCapsules(SearchStore store) {
    final r = store.remoteResult;
    final items = <(String, String, int?)>[
      ('all', '全部', null),
      ('track', '歌曲', r?.tracks?.length),
      ('playlist', '歌单', r?.playlists?.length),
      ('album', '专辑', r?.albums?.length),
      ('artist', '艺人', r?.artists?.length),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (id, title, count) = items[i];
          final active = _tab == id;
          return GestureDetector(
            onTap: () => setState(() => _tab = id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? _tone : MX.fillSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  Text(title,
                      style: TextStyle(
                          color: active ? Colors.white : MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
                  if (count != null) ...[
                    const SizedBox(width: 4),
                    Text('$count',
                        style: TextStyle(
                            color: (active ? Colors.white : MX.fg).withOpacity(active ? 0.85 : 0.55),
                            fontSize: 12)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _status(SearchStore store) {
    final out = <Widget>[];
    if (store.mode == SearchMode.platform && store.targetsError != null) {
      out.add(_notice('平台列表更新失败：${store.targetsError}', '重试', store.loadTargets));
    }
    if (store.remoteError != null) {
      out.add(_notice('搜索失败：${store.remoteError}', store.canLoadMore ? '重试加载' : '重新搜索',
          () => store.canLoadMore ? store.loadMore() : store.retryRemote()));
    } else if (store.remoteLoading) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MX.ember)),
          const SizedBox(width: 8),
          Text(store.remoteResult == null ? '正在搜索…' : '正在加载更多结果…',
              style: TextStyle(color: MX.dim, fontSize: 14)),
        ]),
      ));
    }
    return out;
  }

  Widget _paused(SearchStore store) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 44),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.pause_circle_outline, color: MX.dim, size: 40),
              const SizedBox(height: 8),
              Text('搜索已暂停', style: TextStyle(color: MX.fg, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('不会自动重新提交。', style: TextStyle(color: MX.dim, fontSize: 13)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: store.retryRemote, child: const Text('重新搜索')),
            ],
          ),
        ),
      );

  List<Widget> _resultContent(SearchStore store, SearchResult result) {
    switch (_tab) {
      case 'all':
        return _allResults(store, result);
      case 'playlist':
        return _catalogGrid('歌单', result.playlists ?? [], (p) => _playlistItem(p));
      case 'album':
        return _catalogGrid('专辑', result.albums ?? [], (a) => _albumItem(a));
      case 'artist':
        return _artistGrid(result.artists ?? []);
      default:
        return _trackList(store, result.tracks ?? []);
    }
  }

  List<Widget> _allResults(SearchStore store, SearchResult result) {
    final tracks = result.tracks ?? [];
    final artists = result.artists ?? [];
    final albums = result.albums ?? [];
    final playlists = result.playlists ?? [];
    if (tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty) {
      return [_empty('结果')];
    }
    final out = <Widget>[
      _sectionHeader('最佳结果', null),
      _topResult(store, result),
    ];
    if (tracks.isNotEmpty) {
      out.add(_sectionHeader('歌曲', 'track'));
      for (var i = 0; i < tracks.take(4).length; i++) {
        out.add(TrackRow(track: tracks[i], index: i, queue: tracks));
      }
    }
    if (artists.isNotEmpty) {
      out.add(_sectionHeader('艺人', 'artist'));
      out.add(_horizontalShelf(artists.map((a) => SizedBox(width: 112, child: _artistItem(a))).toList()));
    }
    if (albums.isNotEmpty) {
      out.add(_sectionHeader('专辑', 'album'));
      out.add(_horizontalShelf(albums.map((a) => SizedBox(width: 140, child: _albumItem(a))).toList()));
    }
    if (playlists.isNotEmpty) {
      out.add(_sectionHeader('歌单', 'playlist'));
      out.add(_horizontalShelf(playlists.map((p) => SizedBox(width: 140, child: _playlistItem(p))).toList()));
    }
    return out;
  }

  Widget _topResult(SearchStore store, SearchResult result) {
    final player = context.read<PlayerStore>();
    final ui = context.read<UIStore>();
    final tracks = result.tracks ?? [];
    final query = store.trimmedQuery.toLowerCase();
    int score(String text) {
      final c = text.toLowerCase();
      if (query.isEmpty || c.isEmpty) return 0;
      if (c == query) return 3;
      if (c.startsWith(query)) return 2;
      if (c.contains(query)) return 1;
      return 0;
    }

    Artist? bestArtist;
    for (final a in result.artists ?? []) {
      if (bestArtist == null || score(a.displayName) > score(bestArtist.displayName)) bestArtist = a;
    }
    if (bestArtist != null && score(bestArtist.displayName) >= 2 && score(tracks.isEmpty ? '' : tracks.first.title) < 3) {
      return _topCard(bestArtist.cover, bestArtist.displayName, '', '艺人',
          circle: true, onTap: () => ui.open(ArtistRoute(platform: bestArtist!.platform, id: bestArtist.id)));
    }
    if (tracks.isNotEmpty) {
      final track = tracks.first;
      final current = player.track?.key == track.key;
      return _topCard(track.cover, track.title, track.artistText, '歌曲',
          onTap: () => player.replaceQueue(tracks, start: 0),
          playToggle: () => current ? player.toggle() : player.replaceQueue(tracks, start: 0),
          playing: current && player.playing);
    }
    if (bestArtist != null) {
      return _topCard(bestArtist.cover, bestArtist.displayName, '', '艺人',
          circle: true, onTap: () => ui.open(ArtistRoute(platform: bestArtist!.platform, id: bestArtist.id)));
    }
    if ((result.albums ?? []).isNotEmpty) {
      final album = result.albums!.first;
      return _topCard(album.cover, album.displayTitle, album.artistText, '专辑',
          onTap: () => ui.open(AlbumRoute(platform: album.platform, id: album.id)));
    }
    if ((result.playlists ?? []).isNotEmpty) {
      final p = result.playlists!.first;
      return _topCard(p.cover, p.displayTitle, p.trackCount != null ? '${p.trackCount} 首' : '', '歌单',
          mosaic: p.artTiles, onTap: () => ui.open(_playlistRoute(p)));
    }
    return const SizedBox.shrink();
  }

  Widget _topCard(String? cover, String title, String subtitle, String typeLabel,
      {List<String>? mosaic, bool circle = false, required VoidCallback onTap, VoidCallback? playToggle, bool playing = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: MX.panel, borderRadius: BorderRadius.circular(16)),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoverArt(src: cover, mosaic: mosaic, size: 84, corner: 12, circle: circle),
                const SizedBox(height: 10),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: MX.fg, fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (subtitle.isNotEmpty)
                      Flexible(
                        child: Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: MX.dim, fontSize: 14)),
                      ),
                    if (subtitle.isNotEmpty) const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: MX.fillSoft, borderRadius: BorderRadius.circular(999)),
                      child: Text(typeLabel, style: TextStyle(color: MX.fg, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
            if (playToggle != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: playToggle,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _tone, shape: BoxShape.circle),
                    child: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 22),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _trackList(SearchStore store, List<Track> tracks) {
    if (tracks.isEmpty) return [_empty('歌曲')];
    return [
      _resultsTitle('歌曲', tracks.length),
      Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(color: MX.panel, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            for (var i = 0; i < tracks.length; i++) TrackRow(track: tracks[i], index: i, queue: tracks),
          ],
        ),
      ),
    ];
  }

  List<Widget> _artistGrid(List<Artist> artists) {
    if (artists.isEmpty) return [_empty('艺人')];
    return [
      _resultsTitle('艺人', artists.length),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.78,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
        children: [for (final a in artists) _artistItem(a)],
      ),
    ];
  }

  List<Widget> _catalogGrid<T>(String title, List<T> items, Widget Function(T) builder) {
    if (items.isEmpty) return [_empty(title)];
    return [
      _resultsTitle(title, items.length),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.72,
        crossAxisSpacing: 14,
        mainAxisSpacing: 16,
        children: [for (final it in items) builder(it)],
      ),
    ];
  }

  Widget _artistItem(Artist artist) {
    return CatalogTile(
      cover: artist.cover,
      title: artist.displayName,
      subtitle: '艺人',
      route: ArtistRoute(platform: artist.platform, id: artist.id),
      circle: true,
    );
  }

  Widget _albumItem(Album album) {
    return CatalogTile(
      cover: album.cover,
      title: album.displayTitle,
      subtitle: album.artistText,
      platform: album.platform,
      route: AlbumRoute(platform: album.platform, id: album.id),
    );
  }

  Widget _playlistItem(Playlist p) {
    return CatalogTile(
      cover: p.cover,
      mosaic: p.artTiles,
      title: p.displayTitle,
      subtitle: p.trackCount != null ? '${p.trackCount} 首' : '歌单',
      platform: p.platform,
      route: _playlistRoute(p),
    );
  }

  AppRoute _playlistRoute(Playlist p) => PlaylistRoute(
        platform: p.platform ?? 'local',
        id: p.id,
        kind: p.platform == 'local' ? ListKind.mine : ListKind.platform,
        fromLibrary: false,
      );

  Widget _horizontalShelf(List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      );

  Widget _sectionHeader(String title, String? tabId) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Row(
          children: [
            Text(title, style: TextStyle(color: MX.fg, fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (tabId != null)
              GestureDetector(
                onTap: () => setState(() => _tab = tabId),
                child: Row(
                  children: [
                    Text('查看全部', style: TextStyle(color: MX.dim, fontSize: 14)),
                    Icon(Icons.chevron_right, color: MX.dim, size: 16),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _resultsTitle(String title, int count) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: TextStyle(color: MX.fg, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Text('$count', style: TextStyle(color: MX.dim, fontSize: 14)),
        ],
      );

  Widget _empty(String kind) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 44),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off, color: MX.dim, size: 40),
              const SizedBox(height: 8),
              Text('没有$kind结果', style: TextStyle(color: MX.fg, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('可切换结果类型，或返回选择其他平台。', style: TextStyle(color: MX.dim, fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _notice(String message, String actionTitle, VoidCallback action) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: MX.fillSoft, borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: TextStyle(color: MX.dim, fontSize: 14))),
            TextButton(onPressed: action, child: Text(actionTitle)),
          ],
        ),
      );
}
