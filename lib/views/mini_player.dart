import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/auth_box.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../theme/glass.dart';
import '../theme/theme.dart';

/// Compact playback bar shown above the tab bar. Mirrors Swift `MiniPlayer`
/// (the non-expanded `tabViewBottomAccessory` form). Tapping it opens the full
/// Now Playing surface; a thin progress line rides the top edge.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    final session = context.read<SessionStore>();
    final track = player.track;
    if (track == null) return const SizedBox.shrink();

    final progress = player.duration > 0
        ? (player.current / player.duration).clamp(0.0, 1.0)
        : 0.0;
    final coverUrl = session.api.absolute(track.cover);
    final cookie = AuthBox.shared.combinedCookieHeader();

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: GestureDetector(
        onTap: () => player.setNowPlayingOpen(true),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: coverUrl == null
                          ? _artFallback()
                          : CachedNetworkImage(
                              imageUrl: coverUrl.toString(),
                              httpHeaders: cookie == null ? null : {'Cookie': cookie},
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _artFallback(),
                              errorWidget: (_, __, ___) => _artFallback(),
                            ),
                    ),
                  ),
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
                          style: TextStyle(color: MX.fg, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artistText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MX.mute, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _controlButton(
                    icon: player.loading
                        ? null
                        : (player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    loading: player.loading,
                    onTap: () => player.toggle(),
                  ),
                  _controlButton(
                    icon: Icons.skip_next_rounded,
                    onTap: () => player.next(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 2.5,
                  backgroundColor: MX.fill,
                  valueColor: AlwaysStoppedAnimation(MX.ember),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artFallback() => Container(
        color: MX.fillStrong,
        child: Icon(Icons.music_note_rounded, color: MX.mute, size: 20),
      );

  Widget _controlButton({IconData? icon, bool loading = false, required VoidCallback onTap}) {
    return IconButton(
      onPressed: onTap,
      iconSize: 26,
      color: MX.fg,
      icon: loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: MX.fg),
            )
          : Icon(icon),
    );
  }
}
