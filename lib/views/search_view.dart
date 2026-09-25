import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/search_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/glass.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';
import 'search_results_view.dart';

/// The search tab. Mirrors Swift `SearchView` / `SpotlightSearchContent`:
/// a search field over a suggestion list (history, local matches, an inline
/// platform preview, target rows, genre grid) that pushes a full results page.
class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  SearchStore? _store;
  bool _showMorePlatforms = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = context.read<SessionStore>();
      final key = _activityKey(session);
      setState(() => _store = SearchStore(session: session, activityKey: key));
      _store!.resume();
    });
  }

  String? _activityKey(SessionStore session) {
    final acct = session.accountId;
    if (acct == null || acct.trim().isEmpty || !session.authed) return null;
    return 'spotlight.activity.${session.baseURL}.$acct';
  }

  @override
  void dispose() {
    _controller.dispose();
    _store?.dispose();
    super.dispose();
  }

  void _openResults() {
    final store = _store;
    if (store == null) return;
    Navigator.of(context).push(instantPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: store,
        child: const SearchResultsView(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: MX.ember.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(Icons.travel_explore_rounded, color: MX.ember, size: 20),
            ),
            const SizedBox(width: 11),
            Text('搜索',
                style: TextStyle(
                    color: MX.fg, fontSize: 27, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      body: store == null
          ? Center(child: CircularProgressIndicator(color: MX.ember))
          : ListenableBuilder(
              listenable: store,
              builder: (context, _) => Column(
                children: [
                  _searchField(store),
                  Expanded(child: _list(store)),
                ],
              ),
            ),
    );
  }

  Widget _searchField(SearchStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(18),
        blur: 26,
        showShadow: false,
        padding: EdgeInsets.zero,
        child: TextField(
          controller: _controller,
          style: TextStyle(
              color: MX.fg, fontSize: 16, fontWeight: FontWeight.w500),
          textInputAction: TextInputAction.search,
          onChanged: (text) {
            store.edit(text);
            setState(() => _showMorePlatforms = false);
          },
          onSubmitted: (_) {
            store.submitDefault();
            if (store.mode != SearchMode.suggestions) _openResults();
          },
          decoration: InputDecoration(
            hintText: '歌曲、艺人、专辑、歌单或分享链接',
            hintStyle: TextStyle(color: MX.dim, fontSize: 14),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Icon(Icons.search_rounded, color: MX.ember, size: 23),
            ),
            suffixIcon: store.query.isEmpty
                ? Icon(Icons.graphic_eq_rounded, color: MX.dimSoft, size: 19)
                : IconButton(
                    tooltip: '清除',
                    onPressed: () {
                      _controller.clear();
                      store.edit('');
                      setState(() => _showMorePlatforms = false);
                    },
                    icon: Icon(Icons.close_rounded, color: MX.dim, size: 19),
                  ),
            filled: true,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 17),
          ),
        ),
      ),
    );
  }

  Widget _list(SearchStore store) {
    final session = context.read<SessionStore>();
    if (!session.authed) {
      return _empty(Icons.lock_outline, '请先登录服务器', '本地资料和平台搜索需要登录。');
    }
    final children = <Widget>[];
    if (store.trimmedQuery.isEmpty) {
      children.addAll(_historySection(store));
      children.addAll(_genreSection());
    } else {
      children.addAll(_localSections(store));
      children.addAll(_previewSection(store));
      children.addAll(_targetSection(store));
      if (store.isShareLink) children.add(_shareLinkRow(store));
    }
    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      children: children,
    );
  }

  Widget _empty(IconData icon, String title, String subtitle) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: MX.dim, size: 40),
            const SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: MX.dim, fontSize: 13)),
          ],
        ),
      );

  Widget _header(String title, IconData icon) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: MX.ember.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: MX.ember),
            ),
            const SizedBox(width: 9),
            Text(title,
                style: TextStyle(
                    color: MX.fg, fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  List<Widget> _historySection(SearchStore store) {
    final out = <Widget>[_header('最近搜索', Icons.history)];
    if (store.activity.queries.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: MX.dim),
            const SizedBox(width: 9),
            Expanded(
              child: Text('搜索记录会显示在这里',
                  style: TextStyle(color: MX.dim, fontSize: 13)),
            ),
          ],
        ),
      ));
    } else {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final query in store.activity.queries)
              InputChip(
                avatar: Icon(Icons.history_rounded, size: 15, color: MX.ember),
                label: Text(query),
                labelStyle: TextStyle(color: MX.fg, fontSize: 12.5),
                backgroundColor: MX.panel,
                deleteIcon: Icon(Icons.close_rounded, size: 15, color: MX.dim),
                side: BorderSide(color: MX.hairline),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                onPressed: () {
                  _controller.text = query;
                  store.openHistory(query);
                },
                onDeleted: () => store.removeHistory(query),
              ),
          ],
        ),
      ));
    }
    return out;
  }

  List<Widget> _genreSection() {
    return [
      _header('按曲风探索', Icons.grid_view),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720
                ? 4
                : constraints.maxWidth >= 520
                    ? 3
                    : 2;
            return GridView.builder(
              itemCount: Genre.commonCatalog.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 2.35,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) =>
                  _genreTile(Genre.commonCatalog[index]),
            );
          },
        ),
      ),
    ];
  }

  Widget _genreTile(Genre genre) {
    final visual = _genreVisual(genre.id);
    return Material(
      color: MX.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context
            .read<UIStore>()
            .open(GenreRoute(platform: genre.platform, id: genre.id)),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: visual.$2.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: visual.$2.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(visual.$1, color: visual.$2, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  genre.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MX.fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color) _genreVisual(String id) {
    final key = id.split(':').last;
    switch (key) {
      case 'pop':
      case 'chinese-pop':
        return (Icons.auto_awesome_rounded, const Color(0xFFED5A6B));
      case 'rock':
      case 'metal':
      case 'punk':
        return (Icons.electric_bolt_rounded, const Color(0xFFE18532));
      case 'hip-hop':
      case 'rap':
        return (Icons.mic_rounded, const Color(0xFF8B6BD6));
      case 'rnb':
      case 'soul':
      case 'blues':
        return (Icons.favorite_rounded, const Color(0xFFD85D91));
      case 'electronic':
        return (Icons.graphic_eq_rounded, const Color(0xFF36A7C8));
      case 'folk':
      case 'country':
        return (Icons.nature_people_rounded, const Color(0xFF4C9A73));
      case 'gu-feng':
      case 'world':
        return (Icons.public_rounded, const Color(0xFFB87942));
      case 'classical':
      case 'instrumental':
        return (Icons.piano_rounded, const Color(0xFF6776C8));
      case 'jazz':
        return (Icons.nightlife_rounded, const Color(0xFFB16CB8));
      case 'reggae':
        return (Icons.wb_sunny_rounded, const Color(0xFF4B9D68));
      case 'easy-listening':
        return (Icons.spa_rounded, const Color(0xFF48A596));
      case 'soundtrack':
        return (Icons.movie_filter_rounded, const Color(0xFF547EBE));
      case 'acg':
      case 'japanese-pop':
      case 'korean-pop':
        return (Icons.animation_rounded, const Color(0xFFE16C96));
      default:
        return (Icons.music_note_rounded, MX.ember);
    }
  }

  List<Widget> _localSections(SearchStore store) {
    final out = <Widget>[];
    if (store.localLoading) {
      out.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: MX.ember)),
          const SizedBox(width: 10),
          Text('搜索本地资料…', style: TextStyle(color: MX.dim)),
        ]),
      ));
    }
    if (store.localError != null) {
      out.add(_errorRow('本地检索失败', store.localError!, store.retryLocal));
    }
    final result = store.localResult;
    if (result != null) {
      final tracks = result.tracks ?? [];
      if (tracks.isNotEmpty) {
        out.add(_header('最佳匹配', Icons.star));
        out.add(_topHit(tracks.first, tracks, store));
      }
      if (tracks.length > 1) {
        out.add(_header('本地歌曲', Icons.music_note));
        for (var i = 1; i < tracks.length; i++) {
          out.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TrackRow(track: tracks[i], index: i, queue: tracks),
          ));
        }
      }
      for (final artist in result.artists ?? []) {
        out.add(_suggestionRow(
            Icons.person,
            MX.mute,
            artist.displayName,
            '艺人',
            () => context
                .read<UIStore>()
                .open(ArtistRoute(platform: artist.platform, id: artist.id))));
      }
      for (final album in result.albums ?? []) {
        final route = AlbumRoute(platform: album.platform, id: album.id);
        out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: CatalogListRow(
            cover: album.cover,
            title: album.displayTitle,
            subtitle: album.artistText.isEmpty ? '专辑' : album.artistText,
            platform: album.platform,
            route: route,
          ),
        ));
      }
      for (final playlist in result.playlists ?? []) {
        final route = PlaylistRoute(
            platform: playlist.platform ?? 'local',
            id: playlist.id,
            kind: playlist.platform == 'local'
                ? ListKind.mine
                : ListKind.platform,
            fromLibrary: false);
        out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: CatalogListRow(
            cover: playlist.cover,
            mosaic: playlist.artTiles,
            title: playlist.displayTitle,
            subtitle: playlist.trackCount != null
                ? '${playlist.trackCount} 首'
                : (playlist.platform == 'local'
                    ? '自建歌单'
                    : MX.label(playlist.platform)),
            platform: playlist.platform,
            route: route,
          ),
        ));
      }
      if (tracks.isEmpty &&
          (result.artists ?? []).isEmpty &&
          (result.albums ?? []).isEmpty &&
          (result.playlists ?? []).isEmpty) {
        out.add(Padding(
          padding: const EdgeInsets.all(16),
          child: Text('没有本地匹配，可选择下方平台搜索', style: TextStyle(color: MX.dim)),
        ));
      }
    }
    return out;
  }

  List<Widget> _previewSection(SearchStore store) {
    final result = store.preview;
    final target = store.previewTarget;
    if (result != null && target != null) {
      final tracks = (result.tracks ?? []).take(3).toList();
      if (tracks.isEmpty) return [];
      return [
        _previewHeader(store, target),
        for (var i = 0; i < tracks.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TrackRow(track: tracks[i], index: i, queue: tracks),
          ),
      ];
    }
    if (store.previewLoading && store.defaultTarget != null) {
      final t = store.defaultTarget!;
      return [
        _previewHeader(store, t),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: MX.ember)),
            const SizedBox(width: 10),
            Text('正在${t.name}搜索…', style: TextStyle(color: MX.dim)),
          ]),
        ),
      ];
    }
    return [];
  }

  Widget _previewHeader(SearchStore store, SearchTarget target) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          PlatformMarkBadge(
              platform: target.kind == 'source' ? 'source' : target.platform,
              size: 18),
          const SizedBox(width: 6),
          Text(target.name,
              style: TextStyle(
                  color: MX.dim, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              store.selectTarget(target);
              _openResults();
            },
            child: Row(
              children: [
                Text('查看全部',
                    style: TextStyle(
                        color: MX.ember,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: MX.ember, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _targetSection(SearchStore store) {
    final out = <Widget>[_header('在平台搜索', Icons.search)];
    if (store.remoteError != null) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(store.remoteError!, style: TextStyle(color: MX.dim)),
      ));
    }
    if (store.targetsLoading) {
      out.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: MX.ember)),
          const SizedBox(width: 10),
          Text('加载可用平台…', style: TextStyle(color: MX.dim)),
        ]),
      ));
    } else if (store.targetsError != null) {
      out.add(_errorRow('平台列表加载失败', store.targetsError!, store.loadTargets));
    } else if (store.targets.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text('暂无可用搜索平台', style: TextStyle(color: MX.dim)),
      ));
    } else {
      for (final t in store.suggestedTargets) {
        out.add(_targetRow(store, t));
      }
      if (store.remainingTargets.isNotEmpty) {
        if (_showMorePlatforms) {
          for (final t in store.remainingTargets) {
            out.add(_targetRow(store, t));
          }
        }
        out.add(_suggestionRow(
          _showMorePlatforms ? Icons.expand_less : Icons.more_horiz,
          MX.mute,
          _showMorePlatforms ? '收起平台' : '更多平台',
          _showMorePlatforms ? null : '还有 ${store.remainingTargets.length} 个平台',
          () => setState(() => _showMorePlatforms = !_showMorePlatforms),
          chevron: false,
        ));
      }
    }
    return out;
  }

  Widget _targetRow(SearchStore store, SearchTarget target) {
    final platform = target.kind == 'source' ? 'source' : target.platform;
    final subtitle = target.kind == 'source'
        ? '搜索"${store.trimmedQuery}" · 自定义音源'
        : '搜索"${store.trimmedQuery}"';
    return InkWell(
      onTap: () {
        store.selectTarget(target);
        _openResults();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            PlatformMarkBadge(platform: platform),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(target.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: MX.fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MX.dim, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: MX.dimSoft, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _shareLinkRow(SearchStore store) {
    return Column(
      children: [
        _header('分享链接', Icons.link),
        _suggestionRow(Icons.link, MX.ember, '解析分享链接', '识别输入的分享内容', () {
          store.resolveShare();
          _openResults();
        }),
      ],
    );
  }

  Widget _topHit(Track track, List<Track> queue, SearchStore store) {
    final player = context.read<PlayerStore>();
    return InkWell(
      onTap: () {
        store.recordActionExternal();
        if (queue.isEmpty) {
          player.playNow(track);
        } else {
          player.replaceQueue(queue, start: 0);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CoverArt(src: track.cover, size: 60, corner: 12),
            const SizedBox(width: 14),
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(
                      track.artistText.isEmpty
                          ? MX.label(track.platform)
                          : '${track.artistText} · ${MX.label(track.platform)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MX.dim, fontSize: 13)),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: MX.ember, shape: BoxShape.circle),
              child: Icon(Icons.play_arrow, color: MX.onAccent, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorRow(String title, String message, VoidCallback retry) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warning_amber, color: MX.fg, size: 18),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Text(message, style: TextStyle(color: MX.dim, fontSize: 13)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: retry, child: const Text('重试')),
          ],
        ),
      );

  Widget _suggestionRow(IconData icon, Color tone, String title, String? detail,
      VoidCallback onTap,
      {bool chevron = true}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: tone.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 17, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MX.fg, fontSize: 15)),
                  if (detail != null && detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MX.dim, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (chevron) Icon(Icons.chevron_right, color: MX.dimSoft, size: 16),
          ],
        ),
      ),
    );
  }
}
