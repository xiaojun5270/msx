import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';

enum _NPPage { artwork, queue, lyrics }

/// The full-screen Now Playing surface. Mirrors Swift `NowPlayingView`: an
/// artwork page that flips to a queue or lyrics page, over a blurred-cover
/// backdrop, with transport / progress / volume / footer chrome.
class NowPlayingView extends StatefulWidget {
  const NowPlayingView({super.key});

  @override
  State<NowPlayingView> createState() => _NowPlayingViewState();
}

class _NowPlayingViewState extends State<NowPlayingView> {
  _NPPage _page = _NPPage.artwork;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    final track = player.track;
    final content = _page != _NPPage.artwork;
    return Scaffold(
      backgroundColor: MX.ink,
      body: Stack(
        children: [
          Positioned.fill(child: _Backdrop(src: track?.cover)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  _topBar(player),
                  Expanded(
                    child: _page == _NPPage.artwork
                        ? _artworkPage(player, track)
                        : _page == _NPPage.queue
                            ? _QueuePage(header: _header(player, track))
                            : _LyricsPage(header: _lyricsHeader(player, track)),
                  ),
                  _Progress(compact: content),
                  const SizedBox(height: 6),
                  _Transport(compact: content),
                  if (!content) ...[
                    const SizedBox(height: 10),
                    const _VolumeRow(),
                    const SizedBox(height: 8),
                  ],
                  _footer(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(PlayerStore player) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => player.setNowPlayingOpen(false),
        child: Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.only(top: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle),
          child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Widget _artworkPage(PlayerStore player, Track? track) {
    return Column(
      children: [
        const Spacer(flex: 1),
        LayoutBuilder(builder: (context, c) {
          final side = c.maxWidth.clamp(0.0, 380.0);
          return Container(
            decoration: BoxDecoration(
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 20, offset: const Offset(0, 12))],
            ),
            child: CoverArt(src: track?.cover, size: side, corner: 12),
          );
        }),
        const Spacer(flex: 1),
        _Meta(track: track),
      ],
    );
  }

  Widget _header(PlayerStore player, Track? track) {
    return Row(
      children: [
        CoverArt(src: track?.cover, size: 68, corner: 16),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(track?.title ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(track?.artistText ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
            ],
          ),
        ),
        _FavoriteButton(),
        _MoreMenu(),
      ],
    );
  }

  Widget _lyricsHeader(PlayerStore player, Track? track) {
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [_FavoriteButton(), _MoreMenu()],
      ),
    );
  }

  Widget _footer() {
    Widget mode(IconData icon, bool selected, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white.withOpacity(0.86) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: selected ? MX.ink.withOpacity(0.82) : Colors.white.withOpacity(0.86), size: 22),
          ),
        );
    return Row(
      children: [
        mode(Icons.format_quote, _page == _NPPage.lyrics,
            () => setState(() => _page = _page == _NPPage.lyrics ? _NPPage.artwork : _NPPage.lyrics)),
        const Spacer(),
        Icon(Icons.airplay, color: Colors.white.withOpacity(0.86), size: 22),
        const Spacer(),
        mode(Icons.queue_music, _page == _NPPage.queue,
            () => setState(() => _page = _page == _NPPage.queue ? _NPPage.artwork : _NPPage.queue)),
      ],
    );
  }
}

/// Blurred, dimmed cover backdrop. Mirrors Swift `NowPlayingBackdrop`.
class _Backdrop extends StatelessWidget {
  final String? src;
  const _Backdrop({required this.src});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: MX.ink),
          if (src != null)
            Transform.scale(
              scale: 2.2,
              child: Opacity(
                opacity: 0.7,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                  child: CoverArt(src: src, size: 280, corner: 0),
                ),
              ),
            ),
          Container(color: Colors.black.withOpacity(0.38)),
        ],
      ),
    );
  }
}

/// Title / artist / source badges + favorite/more. Mirrors Swift `NowPlayingMeta`.
class _Meta extends StatelessWidget {
  final Track? track;
  const _Meta({required this.track});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(track?.title ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              _ArtistLine(track: track),
              if (player.trial || (player.sourcePlatform ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (player.trial)
                      Text('试听', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                    if (player.trial && (player.sourcePlatform ?? '').isNotEmpty) const SizedBox(width: 8),
                    if ((player.sourcePlatform ?? '').isNotEmpty)
                      Text(
                          MX.label(player.sourceKind == 'local_replacement' ? 'localfile' : player.sourcePlatform),
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                  ],
                ),
              ],
              if (player.sourceProgress.isVisible) ...[
                const SizedBox(height: 6),
                _SourceStatusLine(),
              ],
            ],
          ),
        ),
        _FavoriteButton(),
        _MoreMenu(),
      ],
    );
  }
}

class _ArtistLine extends StatelessWidget {
  final Track? track;
  const _ArtistLine({required this.track});

  @override
  Widget build(BuildContext context) {
    final entries = track?.artistEntries ?? const [];
    if (entries.isEmpty) {
      return Text(track?.artistText ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 16));
    }
    return Wrap(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) Text(' / ', style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 16)),
          GestureDetector(
            onTap: () => _openArtist(context, entries[i].name, entries[i].id),
            child: Text(entries[i].name,
                style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 16)),
          ),
        ],
      ],
    );
  }

  Future<void> _openArtist(BuildContext context, String name, String id) async {
    final player = context.read<PlayerStore>();
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    final platform = player.track?.platform ?? '';
    final localish = platform == 'localfile' || platform == 'files' || platform == 'local';
    var artistId = (!id.isEmpty && !localish) ? id : '';
    var plat = platform;
    if (artistId.isEmpty) {
      final q = Uri(queryParameters: {
        'name': name,
        if (platform.isNotEmpty) 'preferredPlatform': platform,
      }).query;
      final box = await session.api
          .getJson('/api/resolve/artist?$q', ArtistResolve.fromJson)
          .catchError((_) => const ArtistResolve());
      artistId = box.preferred?.id ?? '';
      plat = box.preferred?.platform ?? platform;
    }
    if (artistId.isEmpty || plat.isEmpty) {
      ui.notify('未找到歌手');
      return;
    }
    player.setNowPlayingOpen(false);
    ui.open(ArtistRoute(platform: plat, id: artistId));
  }
}

class _SourceStatusLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    final progress = player.sourceProgress;
    if (!progress.isVisible) return const SizedBox.shrink();
    final tint = progress.isError ? Colors.orange : Colors.white.withOpacity(0.62);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(progress.isError ? Icons.error_outline : Icons.graphic_eq, size: 13, color: tint),
        const SizedBox(width: 5),
        Flexible(
          child: Text(progress.displayText,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: tint, fontSize: 11)),
        ),
      ],
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    return IconButton(
      onPressed: () => player.toggleFavorite(),
      icon: Icon(player.favorited ? Icons.star : Icons.star_border,
          color: player.favorited ? MX.ember : Colors.white, size: 26),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    final ui = context.read<UIStore>();
    return IconButton(
      icon: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), shape: BoxShape.circle),
        child: const Icon(Icons.more_horiz, color: Colors.white, size: 22),
      ),
      onPressed: () {
        final track = player.track;
        if (track == null) return;
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: MX.panel,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (sheet) {
            Widget item(String label, IconData icon, VoidCallback tap) => ListTile(
                  leading: Icon(icon, color: MX.fg),
                  title: Text(label, style: TextStyle(color: MX.fg)),
                  onTap: () {
                    Navigator.pop(sheet);
                    tap();
                  },
                );
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  item('换源', Icons.swap_horiz, () => ui.openSource(track)),
                  item(player.favorited ? '取消喜欢' : '喜欢',
                      player.favorited ? Icons.star : Icons.star_border, () => player.toggleFavorite()),
                  item('加入歌单', Icons.playlist_add, () => ui.openPicker(track)),
                  const Divider(height: 1),
                  item(player.shuffle ? '关闭随机播放' : '随机播放', Icons.shuffle, () => player.toggleShuffle()),
                  item(_repeatTitle(player.repeatMode),
                      player.repeatMode == 1 ? Icons.repeat_one : Icons.repeat, () => player.cycleRepeat()),
                  const Divider(height: 1),
                  if ((track.albumId ?? '').isNotEmpty)
                    item('前往专辑', Icons.album, () {
                      player.setNowPlayingOpen(false);
                      ui.open(AlbumRoute(platform: track.platform, id: track.albumId!));
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _repeatTitle(int mode) {
    switch (mode) {
      case 1:
        return '单曲循环';
      case 2:
        return '列表循环';
      default:
        return '开启循环';
    }
  }
}

/// The playback queue page. Mirrors Swift `NowPlayingQueueList`.
class _QueuePage extends StatelessWidget {
  final Widget header;
  const _QueuePage({required this.header});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        header,
        const SizedBox(height: 12),
        Row(
          children: [
            Text('继续播放', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
              child: Text('${player.queue.length} 首',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(player.shuffle ? '正在随机播放队列' : '按当前顺序播放',
            style: TextStyle(color: Colors.white.withOpacity(0.66), fontSize: 13)),
        const SizedBox(height: 10),
        Expanded(
          child: player.queue.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.queue_music, color: Colors.white.withOpacity(0.5), size: 40),
                      const SizedBox(height: 8),
                      const Text('暂无播放列表', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: player.queue.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final track = player.queue[i];
                    final current = i == player.index;
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => player.jumpTo(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: current ? Colors.white.withOpacity(0.13) : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Opacity(opacity: current ? 1 : 0.86, child: CoverArt(src: track.cover, size: 50, corner: 10)),
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
                                          color: current ? Colors.white : Colors.white.withOpacity(0.9),
                                          fontSize: 16,
                                          fontWeight: current ? FontWeight.bold : FontWeight.w500)),
                                  const SizedBox(height: 3),
                                  Text(track.artistText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(current ? 0.72 : 0.54), fontSize: 12)),
                                ],
                              ),
                            ),
                            Icon(Icons.drag_handle, color: Colors.white.withOpacity(0.34)),
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
}

/// The lyrics page. Mirrors Swift `NowPlayingLyricsList`.
class _LyricsPage extends StatefulWidget {
  final Widget header;
  const _LyricsPage({required this.header});
  @override
  State<_LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<_LyricsPage> {
  final _scroll = ScrollController();
  int _lastIndex = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToCurrent(int index, int count) {
    if (!_scroll.hasClients || index < 0 || index >= count) return;
    // Approximate row height; center the active line.
    const rowHeight = 46.0;
    final target = (index * rowHeight - _scroll.position.viewportDimension / 2 + rowHeight)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    final lyrics = player.lyrics;
    if (player.lyricIndex != _lastIndex) {
      _lastIndex = player.lyricIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent(player.lyricIndex, lyrics.length));
    }
    return Column(
      children: [
        const SizedBox(height: 24),
        widget.header,
        Expanded(
          child: lyrics.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lyrics_outlined, color: Colors.white.withOpacity(0.5), size: 40),
                      const SizedBox(height: 8),
                      const Text('暂无歌词', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  itemCount: lyrics.length,
                  itemBuilder: (_, i) {
                    final active = i == player.lyricIndex;
                    final text = (lyrics[i].text?.isNotEmpty ?? false) ? lyrics[i].text! : '♪';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(text,
                          style: TextStyle(
                              color: active ? Colors.white : Colors.white.withOpacity(0.48),
                              fontSize: active ? 19 : 16,
                              fontWeight: active ? FontWeight.bold : FontWeight.w500)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Draggable progress bar. Mirrors Swift `NowPlayingProgress`.
class _Progress extends StatefulWidget {
  final bool compact;
  const _Progress({required this.compact});
  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  double _local = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    if (!_dragging) _local = player.current;
    final max = player.duration <= 0 ? 1.0 : player.duration;
    final enabled = !player.loading && player.duration > 0;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withOpacity(0.24),
            thumbColor: Colors.white,
            trackHeight: widget.compact ? 2.5 : 4,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: widget.compact ? 5 : 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: _local.clamp(0, max),
            max: max,
            onChanged: enabled
                ? (v) {
                    setState(() {
                      _dragging = true;
                      _local = v;
                    });
                    player.isSeeking = true;
                  }
                : null,
            onChangeEnd: enabled
                ? (v) {
                    _dragging = false;
                    player.isSeeking = false;
                    player.seek(v);
                  }
                : null,
          ),
        ),
        Row(
          children: [
            Text(fmt(_dragging ? _local : player.current),
                style: TextStyle(
                    color: Colors.white.withOpacity(widget.compact ? 0.54 : 0.62),
                    fontSize: widget.compact ? 11 : 12,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const Spacer(),
            Text('-${fmt((player.duration - player.current).clamp(0, double.infinity))}',
                style: TextStyle(
                    color: Colors.white.withOpacity(widget.compact ? 0.54 : 0.62),
                    fontSize: widget.compact ? 11 : 12,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ],
    );
  }
}

/// Prev / play-pause / next. Mirrors Swift `NowPlayingTransport`.
class _Transport extends StatelessWidget {
  final bool compact;
  const _Transport({required this.compact});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    final side = compact ? 46.0 : 64.0;
    final primary = compact ? 54.0 : 72.0;
    return Row(
      children: [
        _btn(Icons.skip_previous, side, compact ? 30 : 40, () => player.prev()),
        const Spacer(),
        SizedBox(
          width: primary,
          height: primary,
          child: player.loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : IconButton(
                  onPressed: () => player.toggle(),
                  icon: Icon(player.playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white, size: compact ? 44 : 56),
                ),
        ),
        const Spacer(),
        _btn(Icons.skip_next, side, compact ? 30 : 40, () => player.next()),
      ],
    );
  }

  Widget _btn(IconData icon, double box, double size, VoidCallback onTap) => SizedBox(
        width: box,
        height: box,
        child: IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white, size: size)),
      );
}

/// Volume slider row. Mirrors Swift `NowPlayingVolume` (device volume on iOS →
/// the app player volume on Android).
class _VolumeRow extends StatelessWidget {
  const _VolumeRow();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    return Row(
      children: [
        Icon(Icons.volume_down, color: Colors.white.withOpacity(0.62), size: 18),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.28),
              thumbColor: Colors.white,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: player.volume.clamp(0, 1),
              onChanged: (v) => player.setVolume(v),
            ),
          ),
        ),
        Icon(Icons.volume_up, color: Colors.white.withOpacity(0.62), size: 18),
      ],
    );
  }
}
