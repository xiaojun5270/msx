import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../api/auth_box.dart';
import '../models/track.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import 'glass_surfaces.dart';
import '../theme/theme.dart';

/// Collapsible floating player with artwork refraction and full transport.
///
/// Rebuild discipline: the glass shell only rebuilds on discrete state changes
/// (track / playing / loading / favorited / expanded). The position-driven
/// progress row lives in [_SeekRow] and rebuilds alone at ~20 Hz, so the
/// expensive glass panel is not re-rendered every position tick.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  static const collapsedExtent = 88.0;
  static const expandedExtent = 176.0;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    final track = context.select<PlayerStore, Track?>((p) => p.track);
    final playing = context.select<PlayerStore, bool>((p) => p.playing);
    final loading = context.select<PlayerStore, bool>((p) => p.loading);
    final favorited = context.select<PlayerStore, bool>((p) => p.favorited);
    final ui = context.watch<UIStore>();
    final session = context.read<SessionStore>();
    if (track == null) return const SizedBox.shrink();

    final coverUrl = session.api.absolute(track.cover);
    final cookie = AuthBox.shared.combinedCookieHeader();
    final headers = cookie == null ? null : {'Cookie': cookie};
    final expanded = ui.playerExpanded;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -180 && !expanded) ui.setPlayerExpanded(true);
            if (velocity > 180 && expanded) ui.setPlayerExpanded(false);
          },
          child: MusicGlassPanel(
            refractBackground: true,
            radius: expanded ? 28 : 34,
            quality: GlassQuality.standard,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: expanded
                  ? _expandedPlayer(
                      context,
                      player,
                      track.title,
                      track.artistText,
                      coverUrl,
                      headers,
                      favorited,
                      playing,
                      loading,
                    )
                  : _collapsedPlayer(
                      context,
                      player,
                      track.title,
                      track.artistText,
                      coverUrl,
                      headers,
                      favorited,
                      playing,
                      loading,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _collapsedPlayer(
    BuildContext context,
    PlayerStore player,
    String title,
    String artist,
    Uri? coverUrl,
    Map<String, String>? headers,
    bool favorited,
    bool playing,
    bool loading,
  ) {
    return SizedBox(
      key: const ValueKey('collapsed-player'),
      height: 78,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            _artwork(coverUrl, headers, size: 60, radius: 17),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.read<UIStore>().setPlayerExpanded(true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MX.fg,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MX.mute, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _compactButton(
              tooltip: favorited ? '取消收藏' : '收藏',
              icon: favorited
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: favorited ? MX.ember : MX.fg,
              onPressed: () => player.toggleFavorite(),
            ),
            _compactPlayButton(player, playing, loading),
            _compactButton(
              tooltip: '播放队列',
              icon: Icons.queue_music_rounded,
              onPressed: () => context.read<UIStore>().openQueue(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expandedPlayer(
    BuildContext context,
    PlayerStore player,
    String title,
    String artist,
    Uri? coverUrl,
    Map<String, String>? headers,
    bool favorited,
    bool playing,
    bool loading,
  ) {
    return Padding(
      key: const ValueKey('expanded-player'),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => player.setNowPlayingOpen(true),
                child: _artwork(coverUrl, headers, size: 52, radius: 12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => player.setNowPlayingOpen(true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MX.fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MX.mute, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '收起播放器',
                onPressed: () =>
                    context.read<UIStore>().setPlayerExpanded(false),
                icon: Icon(Icons.keyboard_arrow_down_rounded,
                    color: MX.fg, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _SeekRow(player: player),
          SizedBox(
            height: 50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _iconButton(
                  tooltip: favorited ? '取消收藏' : '收藏',
                  icon: favorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: favorited ? MX.ember : MX.fg,
                  onPressed: () => player.toggleFavorite(),
                ),
                _iconButton(
                  tooltip: '上一首',
                  icon: Icons.skip_previous_rounded,
                  iconSize: 30,
                  onPressed: () => player.prev(),
                ),
                _playButton(context, player, playing, loading),
                _iconButton(
                  tooltip: '下一首',
                  icon: Icons.skip_next_rounded,
                  iconSize: 30,
                  onPressed: () => player.next(),
                ),
                _iconButton(
                  tooltip: '播放队列',
                  icon: Icons.queue_music_rounded,
                  onPressed: () => context.read<UIStore>().openQueue(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _artwork(
    Uri? coverUrl,
    Map<String, String>? headers, {
    required double size,
    required double radius,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: coverUrl == null
            ? _artFallback()
            : CachedNetworkImage(
                imageUrl: coverUrl.toString(),
                httpHeaders: headers,
                fit: BoxFit.cover,
                placeholder: (_, __) => _artFallback(),
                errorWidget: (_, __, ___) => _artFallback(),
              ),
      ),
    );
  }

  Widget _compactPlayButton(PlayerStore player, bool playing, bool loading) {
    return SizedBox(
      width: 42,
      height: 48,
      child: IconButton(
        tooltip: loading ? '取消加载' : (playing ? '暂停' : '播放'),
        padding: EdgeInsets.zero,
        onPressed: () => player.toggle(),
        icon: loading
            ? SizedBox(
                width: 21,
                height: 21,
                child: CircularProgressIndicator(strokeWidth: 2, color: MX.fg),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: MX.fg,
                size: 31,
              ),
      ),
    );
  }

  Widget _compactButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return SizedBox(
      width: 40,
      height: 48,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        color: color ?? MX.fg,
        iconSize: 27,
        icon: Icon(icon),
      ),
    );
  }

  /// Solid accent disc — high contrast against any glass material, echoing the
  /// hero card's round play/pause affordance.
  Widget _playButton(
      BuildContext context, PlayerStore player, bool playing, bool loading) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: MX.ember,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: MX.ember.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        tooltip: loading ? '取消加载' : (playing ? '暂停' : '播放'),
        padding: EdgeInsets.zero,
        onPressed: () => player.toggle(),
        icon: loading
            ? SizedBox(
                width: 21,
                height: 21,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: MX.onAccent),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: MX.onAccent,
                size: 28,
              ),
      ),
    );
  }

  Widget _iconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
    double iconSize = 25,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      color: color ?? MX.fg,
      iconSize: iconSize,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon),
    );
  }

  Widget _artFallback() => Container(
        color: MX.fillStrong,
        alignment: Alignment.center,
        child: Icon(Icons.music_note_rounded, color: MX.mute, size: 23),
      );

  String _time(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return '0:00';
    final total = seconds.floor();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

/// Position-driven row isolated from the glass shell: rebuilds alone on each
/// position tick so the glass panel never re-renders at playback frequency.
class _SeekRow extends StatelessWidget {
  final PlayerStore player;
  const _SeekRow({required this.player});

  @override
  Widget build(BuildContext context) {
    final current = context.select<PlayerStore, double>((p) => p.current);
    final duration = context.select<PlayerStore, double>((p) => p.duration);
    final effective = duration > 0 ? duration : 1.0;
    return Row(
      children: [
        Text(_time(current), style: TextStyle(color: MX.dim, fontSize: 10.5)),
        Expanded(
          child: SizedBox(
            height: 30,
            // A plain Slider: the glass slider rebuilt its own material on
            // every 50 ms position tick and its lens thumb read as a smudge
            // over the frosted panel.
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: MX.ember,
                inactiveTrackColor: MX.fg.withOpacity(0.18),
                thumbColor: MX.ember,
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6, elevation: 1.5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                label: '播放进度',
                value: current.clamp(0.0, effective),
                max: effective,
                onChanged: duration > 0 ? player.seek : null,
              ),
            ),
          ),
        ),
        Text(_time(duration), style: TextStyle(color: MX.dim, fontSize: 10.5)),
      ],
    );
  }

  String _time(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return '0:00';
    final total = seconds.floor();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}
