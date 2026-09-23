import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/auth_box.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/glass.dart';
import '../theme/theme.dart';

/// Collapsible floating player with artwork refraction and full transport.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    final ui = context.watch<UIStore>();
    final session = context.read<SessionStore>();
    final track = player.track;
    if (track == null) return const SizedBox.shrink();

    final coverUrl = session.api.absolute(track.cover);
    final cookie = AuthBox.shared.combinedCookieHeader();
    final headers = cookie == null ? null : {'Cookie': cookie};
    final duration = player.duration > 0 ? player.duration : track.duration;
    final current =
        duration > 0 ? player.current.clamp(0.0, duration).toDouble() : 0.0;
    final expanded = ui.playerExpanded;

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
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
          child: LiquidGlassPanel(
            borderRadius: BorderRadius.circular(expanded ? 28 : 34),
            blurSigma: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
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
                      current,
                      duration,
                    )
                  : _collapsedPlayer(
                      context,
                      player,
                      track.title,
                      track.artistText,
                      coverUrl,
                      headers,
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
              tooltip: player.favorited ? '取消收藏' : '收藏',
              icon: player.favorited
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: player.favorited ? MX.ember : MX.fg,
              onPressed: () => player.toggleFavorite(),
            ),
            _compactPlayButton(player),
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
    double current,
    double duration,
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
          const SizedBox(height: 6),
          Row(
            children: [
              Text(_time(current),
                  style: TextStyle(color: MX.dim, fontSize: 10.5)),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      activeTrackColor: MX.fg.withOpacity(0.82),
                      inactiveTrackColor: MX.fg.withOpacity(0.16),
                      thumbColor: MX.fg,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: current,
                      max: duration > 0 ? duration : 1,
                      onChanged: duration > 0 ? player.seek : null,
                    ),
                  ),
                ),
              ),
              Text(_time(duration),
                  style: TextStyle(color: MX.dim, fontSize: 10.5)),
            ],
          ),
          SizedBox(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _iconButton(
                  tooltip: player.favorited ? '取消收藏' : '收藏',
                  icon: player.favorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: player.favorited ? MX.ember : MX.fg,
                  onPressed: () => player.toggleFavorite(),
                ),
                _iconButton(
                  tooltip: '上一首',
                  icon: Icons.skip_previous_rounded,
                  iconSize: 29,
                  onPressed: () => player.prev(),
                ),
                _playButton(context, player),
                _iconButton(
                  tooltip: '下一首',
                  icon: Icons.skip_next_rounded,
                  iconSize: 29,
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

  Widget _compactPlayButton(PlayerStore player) {
    return SizedBox(
      width: 42,
      height: 48,
      child: IconButton(
        tooltip: player.loading ? '取消加载' : (player.playing ? '暂停' : '播放'),
        padding: EdgeInsets.zero,
        onPressed: () => player.toggle(),
        icon: player.loading
            ? SizedBox(
                width: 21,
                height: 21,
                child: CircularProgressIndicator(strokeWidth: 2, color: MX.fg),
              )
            : Icon(
                player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
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

  Widget _playButton(BuildContext context, PlayerStore player) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: MX.fg.withOpacity(dark ? 0.08 : 0.06),
        shape: BoxShape.circle,
        border: Border.all(color: MX.fg.withOpacity(0.62), width: 1.2),
      ),
      child: IconButton(
        tooltip: player.loading ? '取消加载' : (player.playing ? '暂停' : '播放'),
        padding: EdgeInsets.zero,
        onPressed: () => player.toggle(),
        icon: player.loading
            ? SizedBox(
                width: 21,
                height: 21,
                child: CircularProgressIndicator(strokeWidth: 2, color: MX.fg),
              )
            : Icon(
                player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: MX.fg,
                size: 30,
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
