import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/auth_box.dart';
import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/artwork_color.dart';
import '../theme/route.dart';
import '../theme/theme.dart';

/// Format seconds as m:ss. Mirrors Swift `fmt`.
String fmt(double sec) {
  if (!sec.isFinite || sec <= 0) return '0:00';
  final s = sec.toInt();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

Map<String, String>? _cookieHeaders() {
  final cookie = AuthBox.shared.combinedCookieHeader();
  return cookie == null ? null : {'Cookie': cookie};
}

/// Cover artwork with rounded corners, cookie-authenticated remote loading,
/// data-URL support, and a mosaic grid fallback. Mirrors Swift `CoverArt`.
/// (Motion/video covers are omitted on Android — a still cover is shown.)
class CoverArt extends StatelessWidget {
  final String? src;
  final List<String>? mosaic;
  final double? size;
  final double? height;
  final double corner;
  final bool circle;

  const CoverArt({
    super.key,
    required this.src,
    this.mosaic,
    this.size,
    this.height,
    this.corner = 8,
    this.circle = false,
  });

  double get _h => height ?? size ?? 48;
  double get _w => size ?? _h;

  @override
  Widget build(BuildContext context) {
    final api = context.read<SessionStore>().api;
    final radius = circle ? BorderRadius.circular(_w.clamp(0, _h) / 2 + _h) : BorderRadius.circular(corner);
    Widget child;

    final dataImg = (src != null && src!.startsWith('data:image')) ? dataUrlImage(src!) : null;
    final resolved = api.absolute(src);
    if (dataImg != null) {
      child = Image(image: dataImg, width: _w, height: _h, fit: BoxFit.cover);
    } else if (resolved != null) {
      child = CachedNetworkImage(
        imageUrl: resolved.toString(),
        httpHeaders: _cookieHeaders(),
        width: _w,
        height: _h,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      );
    } else {
      final tiles = _mosaicTiles;
      child = tiles != null ? _mosaicGrid(api, tiles) : _placeholder();
    }

    return ClipRRect(
      borderRadius: circle ? BorderRadius.circular(9999) : BorderRadius.circular(corner),
      child: SizedBox(width: size, height: height ?? size, child: child),
    );
  }

  List<String>? get _mosaicTiles {
    final urls = (mosaic ?? []).where((s) => s.isNotEmpty).toList();
    if (urls.isEmpty) return null;
    if (urls.length == 1) return urls;
    final out = [...urls];
    while (out.length < 9) {
      out.add(urls[out.length % urls.length]);
    }
    return out.take(9).toList();
  }

  Widget _mosaicGrid(dynamic api, List<String> tiles) {
    if (tiles.length == 1) {
      final u = api.absolute(tiles[0]);
      if (u != null) {
        return CachedNetworkImage(
            imageUrl: u.toString(), httpHeaders: _cookieHeaders(), fit: BoxFit.cover);
      }
    }
    return GridView.count(
      crossAxisCount: 3,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final t in tiles)
          Builder(builder: (_) {
            final u = api.absolute(t);
            return u == null
                ? Container(color: MX.fill)
                : CachedNetworkImage(
                    imageUrl: u.toString(), httpHeaders: _cookieHeaders(), fit: BoxFit.cover);
          }),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      width: _w,
      height: _h,
      color: MX.fill,
      alignment: Alignment.center,
      child: Icon(Icons.music_note,
          size: (_w.clamp(0, _h) * 0.32).clamp(12, 48), color: MX.dimSoft.withOpacity(0.7)),
    );
  }
}

/// A tappable track row. Mirrors Swift `TrackRow`.
class TrackRow extends StatelessWidget {
  final Track track;
  final int index;
  final List<Track> queue;
  final bool selected;
  final bool selecting;
  final VoidCallback? onSelect;
  final VoidCallback? onDelete;

  const TrackRow({
    super.key,
    required this.track,
    this.index = 0,
    this.queue = const [],
    this.selected = false,
    this.selecting = false,
    this.onSelect,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    final current = player.track?.key == track.key;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (onSelect != null) {
          onSelect!();
          return;
        }
        if (queue.isEmpty) {
          player.playNow(track);
        } else {
          player.replaceQueue(queue, start: index);
        }
      },
      onLongPress: () => showTrackActions(context, track, onDelete: onDelete),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? MX.fillStrong : (current ? MX.fillSoft : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? MX.ember : MX.dimSoft),
              ),
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
                          color: current ? MX.ember : MX.fg, fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(track.artistText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: MX.dim, fontSize: 12)),
                      ),
                      if (track.platform.isNotEmpty) ...[
                        Text('  ·  ', style: TextStyle(color: MX.dimSoft, fontSize: 12)),
                        Text(MX.label(track.platform),
                            style: TextStyle(color: MX.dimSoft, fontSize: 11)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!selecting && (track.durationMs ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(fmt((track.durationMs ?? 0) / 1000),
                    style: TextStyle(
                        color: MX.dimSoft, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
          ],
        ),
      ),
    );
  }
}

/// Numbered catalog row used in playlist/album detail. Mirrors `CatalogTrackRow`.
class CatalogTrackRow extends StatelessWidget {
  final Track track;
  final int index;
  final List<Track> queue;
  final void Function(Track)? onRemove;
  final bool isNew;

  const CatalogTrackRow({
    super.key,
    required this.track,
    this.index = 0,
    this.queue = const [],
    this.onRemove,
    this.isNew = false,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerStore>();
    final current = player.track?.key == track.key;
    return Container(
      decoration: BoxDecoration(
        color: current ? MX.fillSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border(bottom: BorderSide(color: MX.line, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                if (queue.isEmpty) {
                  player.playNow(track);
                } else {
                  player.replaceQueue(queue, start: index);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: current ? MX.ember.withOpacity(0.12) : MX.fillSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${index + 1}',
                          style: TextStyle(
                              color: current ? MX.ember : MX.dimSoft,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: current ? MX.ember : MX.fg,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500)),
                              ),
                              if (isNew)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(999)),
                                  child: const Text('NEW',
                                      style: TextStyle(
                                          color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          if (track.artistText.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(track.artistText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: MX.dim, fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => showTrackActions(context, track, onRemove: onRemove),
            icon: Icon(Icons.more_horiz, color: MX.mute),
          ),
        ],
      ),
    );
  }
}

/// Present the track action sheet. Mirrors Swift `TrackActions` context menu.
void showTrackActions(BuildContext context, Track track,
    {VoidCallback? onDelete, void Function(Track)? onRemove}) {
  final player = context.read<PlayerStore>();
  final ui = context.read<UIStore>();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: MX.panel,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) {
      Widget item(String label, IconData icon, VoidCallback onTap, {bool destructive = false}) {
        final color = destructive ? const Color(0xFFE0434F) : MX.fg;
        return ListTile(
          leading: Icon(icon, color: color),
          title: Text(label, style: TextStyle(color: color)),
          onTap: () {
            Navigator.pop(sheetContext);
            onTap();
          },
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  CoverArt(src: track.cover, size: 44, corner: 6),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: MX.fg, fontWeight: FontWeight.w600)),
                        Text(track.artistText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: MX.dim, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: MX.line, height: 1),
            item('下一首播放', Icons.playlist_play, () => player.playNext(track)),
            item('加入队列', Icons.queue_music, () => player.enqueue(track)),
            item('收藏', Icons.favorite_border, () => player.toggleFavorite(track)),
            item('加入歌单', Icons.playlist_add, () => ui.openPicker(track)),
            item('换源', Icons.swap_horiz, () => ui.openSource(track)),
            item('整理音源', Icons.auto_fix_high, () => ui.openOrganization([track])),
            if (onRemove != null)
              item('从歌单移除', Icons.remove_circle_outline, () => onRemove(track), destructive: true),
            if (onDelete != null)
              item('删除记录', Icons.delete_outline, onDelete, destructive: true),
          ],
        ),
      );
    },
  );
}

/// Muted-artwork gradient backdrop. Mirrors Swift `ArtworkBackdrop`.
class ArtworkBackdrop extends StatelessWidget {
  final Color color;
  const ArtworkBackdrop({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.32, 0.62, 1],
          colors: [color, color, MX.ink.withOpacity(0.88), MX.ink],
        ),
      ),
    );
  }
}

/// Section heading. Mirrors Swift `SectionTitle`.
class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Text(title,
      style: TextStyle(color: MX.fg, fontSize: 22, fontWeight: FontWeight.bold));
}

/// A small platform icon chip. Mirrors Swift `PlatformChip`.
class PlatformChip extends StatelessWidget {
  final String id;
  final bool showLabel;
  const PlatformChip({super.key, required this.id, this.showLabel = false});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(MX.icon(id), size: 12, color: MX.tone(id)),
        if (showLabel) ...[
          const SizedBox(width: 5),
          Text(MX.label(id), style: TextStyle(color: MX.dim, fontSize: 11)),
        ],
      ],
    );
  }
}

/// Square platform mark badge. Mirrors Swift `PlatformMarkBadge`.
class PlatformMarkBadge extends StatelessWidget {
  final String platform;
  final double size;
  const PlatformMarkBadge({super.key, required this.platform, this.size = 34});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: MX.tone(platform), borderRadius: BorderRadius.circular(size * 0.29)),
      child: Text(MX.mark(platform),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }
}

/// A catalog cover tile that navigates to [route] on tap. Mirrors `CatalogTile`.
class CatalogTile extends StatelessWidget {
  final String? cover;
  final List<String>? mosaic;
  final String title;
  final String subtitle;
  final String? platform;
  final AppRoute route;
  final bool circle;

  const CatalogTile({
    super.key,
    this.cover,
    this.mosaic,
    required this.title,
    required this.subtitle,
    this.platform,
    required this.route,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.read<UIStore>().open(route),
      child: Column(
        crossAxisAlignment: circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Positioned.fill(child: CoverArt(src: cover, mosaic: mosaic, corner: 12, circle: circle)),
                if (platform != null && platform!.isNotEmpty && platform != 'local' && !circle)
                  Positioned(left: 8, top: 8, child: PlatformChip(id: platform!)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w600)),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: circle ? TextAlign.center : TextAlign.start,
                style: TextStyle(color: MX.mute, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Horizontal catalog list row. Mirrors Swift `CatalogListRow`.
class CatalogListRow extends StatelessWidget {
  final String? cover;
  final List<String>? mosaic;
  final String title;
  final String subtitle;
  final String? platform;
  final AppRoute route;
  final bool circle;

  const CatalogListRow({
    super.key,
    this.cover,
    this.mosaic,
    required this.title,
    required this.subtitle,
    this.platform,
    required this.route,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.read<UIStore>().open(route),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            CoverArt(src: cover, mosaic: mosaic, size: 54, corner: 8, circle: circle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MX.fg, fontSize: 15, fontWeight: FontWeight.w500)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (platform != null && platform!.isNotEmpty && platform != 'local') ...[
                          PlatformChip(id: platform!),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: MX.dim, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The big collection hero (cover + title + play/shuffle). Mirrors `CollectionHero`.
class CollectionHero extends StatelessWidget {
  final String? cover;
  final List<String>? mosaic;
  final String title;
  final String subtitle;
  final bool canPlay;
  final IconData plusIcon;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback? onPlus;
  final bool circle;

  const CollectionHero({
    super.key,
    this.cover,
    this.mosaic,
    required this.title,
    required this.subtitle,
    this.canPlay = false,
    this.plusIcon = Icons.add,
    required this.onPlay,
    required this.onShuffle,
    this.onPlus,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.of(context).size.width > 600 ? 260.0 : 220.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 22, offset: const Offset(0, 14))],
            ),
            child: CoverArt(src: cover, mosaic: mosaic, size: side, corner: 10, circle: circle),
          ),
          const SizedBox(height: 16),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _round(Icons.shuffle, '随机播放', canPlay ? onShuffle : null),
              const SizedBox(width: 14),
              FilledButton.icon(
                onPressed: canPlay ? onPlay : null,
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('播放'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: const StadiumBorder(),
                ),
              ),
              const SizedBox(width: 14),
              if (onPlus != null)
                _round(plusIcon, '添加', onPlus)
              else
                const SizedBox(width: 36, height: 36),
            ],
          ),
        ],
      ),
    );
  }

  Widget _round(IconData icon, String label, VoidCallback? action) {
    return Semantics(
      label: label,
      button: true,
      child: Opacity(
        opacity: action == null ? 0.4 : 1,
        child: GestureDetector(
          onTap: action,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

/// A segmented chip bar. Mirrors Swift `SegmentBar` (multi-select-off toggle).
/// Horizontal filter chips. Mirrors Swift `ChipBar` (single-select, always
/// keeps a selection). Same shape as [SegmentBar] but never clears on re-tap.
class ChipBar extends StatelessWidget {
  final List<(String, String)> items;
  final String selected;
  final ValueChanged<String> onChanged;
  const ChipBar({super.key, required this.items, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (id, title) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(title),
                selected: selected == id,
                onSelected: (_) => onChanged(id),
                selectedColor: MX.ember.withOpacity(0.2),
                labelStyle: TextStyle(color: selected == id ? MX.ember : MX.mute),
                backgroundColor: MX.fill,
                side: BorderSide(color: MX.line),
              ),
            ),
        ],
      ),
    );
  }
}

class SegmentBar extends StatelessWidget {
  final List<(String, String)> items;
  final String selected;
  final ValueChanged<String> onChanged;
  const SegmentBar({super.key, required this.items, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (id, title) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(title),
                selected: selected == id,
                onSelected: (_) => onChanged(selected == id ? '' : id),
                selectedColor: MX.ember.withOpacity(0.2),
                labelStyle: TextStyle(color: selected == id ? MX.ember : MX.mute),
                backgroundColor: MX.fill,
                side: BorderSide(color: MX.line),
              ),
            ),
        ],
      ),
    );
  }
}

/// Skeleton placeholder bar. Mirrors Swift `SkeletonBar` (with pulse).
class SkeletonBar extends StatefulWidget {
  final double? width;
  final double height;
  final double corner;
  const SkeletonBar({super.key, this.width, this.height = 12, this.corner = 4});
  @override
  State<SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<SkeletonBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(MX.fill, MX.fillStrong, _c.value),
          borderRadius: BorderRadius.circular(widget.corner),
        ),
      ),
    );
  }
}

/// Track-row skeleton. Mirrors Swift `TrackRowSkeleton`.
class TrackRowSkeleton extends StatelessWidget {
  const TrackRowSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          const SkeletonBar(width: 48, height: 48, corner: 6),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBar(width: 168, height: 16),
              SizedBox(height: 6),
              SkeletonBar(width: 108, height: 13),
            ],
          ),
          const Spacer(),
          const SkeletonBar(width: 32, height: 10),
        ],
      ),
    );
  }
}

/// Hero background color loader — resolves a muted color from the artwork.
class HeroColor extends StatefulWidget {
  final String? src;
  final Widget Function(Color color) builder;
  const HeroColor({super.key, required this.src, required this.builder});
  @override
  State<HeroColor> createState() => _HeroColorState();
}

class _HeroColorState extends State<HeroColor> {
  Color _color = MX.heroBase;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant HeroColor old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src) _resolve();
  }

  Future<void> _resolve() async {
    final api = context.read<SessionStore>().api;
    final c = await ArtworkColor.load(widget.src, api);
    if (mounted) setState(() => _color = c);
  }

  @override
  Widget build(BuildContext context) => widget.builder(_color);
}
