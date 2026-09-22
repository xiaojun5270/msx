import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/auth_box.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/glass.dart';
import '../theme/theme.dart';

/// Floating player chrome with artwork refraction, seek, and full transport.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    final session = context.read<SessionStore>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final track = player.track;
    if (track == null) return const SizedBox.shrink();

    final coverUrl = session.api.absolute(track.cover);
    final cookie = AuthBox.shared.combinedCookieHeader();
    final headers = cookie == null ? null : {'Cookie': cookie};
    final duration = player.duration > 0 ? player.duration : track.duration;
    final current =
        duration > 0 ? player.current.clamp(0.0, duration).toDouble() : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(28),
        blur: 38,
        tint: dark
            ? const Color.fromRGBO(31, 29, 33, 0.62)
            : const Color.fromRGBO(255, 255, 255, 0.66),
        child: Stack(
          children: [
            if (coverUrl != null)
              Positioned.fill(
                child: Opacity(
                  opacity: dark ? 0.22 : 0.13,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Transform.scale(
                      scale: 1.35,
                      child: CachedNetworkImage(
                        imageUrl: coverUrl.toString(),
                        httpHeaders: headers,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? [
                            Colors.black.withOpacity(0.12),
                            Colors.black.withOpacity(0.38)
                          ]
                        : [
                            Colors.white.withOpacity(0.16),
                            Colors.white.withOpacity(0.46)
                          ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => player.setNowPlayingOpen(true),
                    child: Row(
                      children: [
                        _artwork(coverUrl, headers),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track.title,
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
                                track.artistText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(color: MX.mute, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.keyboard_arrow_up_rounded,
                            color: MX.dim, size: 28),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
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
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 4.5),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _artwork(Uri? coverUrl, Map<String, String>? headers) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 52,
        height: 52,
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

  Widget _playButton(BuildContext context, PlayerStore player) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: MX.fg.withOpacity(dark ? 0.10 : 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: MX.fg.withOpacity(0.72), width: 1.4),
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
