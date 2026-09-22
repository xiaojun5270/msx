import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/theme.dart';
import 'components.dart';

/// Header + drag chrome shared by the aux sheets (mirrors the SwiftUI
/// `.presentationDetents` / `.presentationDragIndicator` sheet look).
Widget _sheetFrame({
  required String title,
  required ScrollController controller,
  required Widget body,
  List<Widget>? actions,
}) {
  return Builder(
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: MX.ink,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: MX.hairline),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: MX.dimSoft, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(title, style: TextStyle(color: MX.fg, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (actions != null) ...actions,
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text('关闭', style: TextStyle(color: MX.ember)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: MX.line),
          Expanded(child: Scrollbar(controller: controller, child: body)),
        ],
      ),
    ),
  );
}

/// Present one of the aux sheets as a rounded modal bottom sheet.
Future<void> showAuxSheet(BuildContext context, Widget sheet) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => _SheetControllerScope(controller: controller, child: sheet),
    ),
  );
}

/// Provides the DraggableScrollableSheet's controller to the sheet body.
class _SheetControllerScope extends InheritedWidget {
  final ScrollController controller;
  const _SheetControllerScope({required this.controller, required super.child});

  static ScrollController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetControllerScope>()!.controller;

  @override
  bool updateShouldNotify(_SheetControllerScope oldWidget) => controller != oldWidget.controller;
}

// __APPEND_QUEUE_SHEET__

/// 队列 — current playback queue with jump-to.
class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = _SheetControllerScope.of(context);
    final player = context.watch<PlayerStore>();
    final queue = player.queue;
    return _sheetFrame(
      title: '队列',
      controller: controller,
      body: queue.isEmpty
          ? Center(child: Text('队列为空', style: TextStyle(color: MX.mute, fontSize: 14)))
          : ListView.builder(
              controller: controller,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: queue.length,
              itemBuilder: (context, i) {
                final t = queue[i];
                final current = i == player.index;
                return InkWell(
                  onTap: () => context.read<PlayerStore>().jumpTo(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text('${i + 1}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: MX.dimSoft,
                                  fontSize: 13,
                                  fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: current ? MX.ember : MX.fg, fontSize: 15)),
                              if (t.artistText.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(t.artistText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: MX.mute, fontSize: 12)),
                              ],
                            ],
                          ),
                        ),
                        if (current)
                          Icon(Icons.volume_up, size: 16, color: MX.ember),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// __APPEND_SOURCE_SHEET__

/// 换源 — candidate sources for the selected track.
class SourceSheet extends StatefulWidget {
  const SourceSheet({super.key});
  @override
  State<SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<SourceSheet> {
  List<Track> _list = [];
  bool _loading = true;
  bool _applying = false;
  String? _applyMessage;
  int? _sourceVersion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool refresh = false}) async {
    final ui = context.read<UIStore>();
    final api = context.read<SessionStore>().api;
    final track = ui.sourceTrack;
    if (track == null) return;
    if (!refresh && _list.isEmpty) setState(() => _loading = true);
    _sourceVersion = null;
    try {
      if (!refresh) {
        final cached = await api.sourceContext(track);
        if (ui.sourceTrack?.key != track.key) return;
        if (cached.candidates.isNotEmpty) {
          setState(() {
            _sourceVersion = cached.version;
            _list = cached.candidates;
            _loading = false;
          });
          return;
        }
      }
      setState(() => _loading = true);
      final ctx = await api.sourceCandidates(track, refresh: refresh);
      if (ui.sourceTrack?.key != track.key) return;
      if (mounted) {
        setState(() {
          _sourceVersion = ctx.version;
          _list = ctx.candidates;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_list.isEmpty) _applyMessage = '$e';
        });
      }
    }
  }

  Future<void> _apply(Track candidate) async {
    final ui = context.read<UIStore>();
    final player = context.read<PlayerStore>();
    final original = ui.sourceTrack;
    final version = _sourceVersion;
    if (original == null || version == null) return;
    setState(() => _applying = true);
    try {
      final outcome = await player.applySource(candidate, original, version: version);
      if (!mounted) return;
      setState(() {
        _applying = false;
        _applyMessage = outcome.message;
      });
      if (outcome.saved) {
        ui.notify(outcome.message);
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) setState(() => _applying = false);
      _applyMessage = '$e';
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _SheetControllerScope.of(context);
    final ui = context.watch<UIStore>();
    final session = context.watch<SessionStore>();
    final player = context.watch<PlayerStore>();
    final head = ui.sourceTrack;

    return _sheetFrame(
      title: '换源',
      controller: controller,
      body: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (head != null) ...[
            Row(
              children: [
                CoverArt(src: head.cover, size: 48, corner: 6),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(head.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
                      if (head.artistText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(head.artistText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: MX.mute, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Text('候选音源 · 验证并保存后生效', style: TextStyle(color: MX.mute, fontSize: 12)),
          const SizedBox(height: 8),
          if (_loading)
            for (int i = 0; i < 4; i++)
              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: SkeletonBar(height: 48))
          else if (_list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('暂无其他音源', style: TextStyle(color: MX.mute, fontSize: 14))),
            )
          else
            for (final t in _list)
              _SourceRow(
                track: t,
                current: ui.sourceTrack?.key == player.track?.key && t.key == player.selectedSourceKey,
                bound: session.bindings[t.platform]?.bound == true,
                onTap: _applying ? null : () => _apply(t),
              ),
          if (_applying) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('验证并保存音源…', style: TextStyle(color: MX.mute, fontSize: 13)),
              ],
            ),
          ],
          if (_applyMessage != null && !_applying) ...[
            const SizedBox(height: 12),
            Text(_applyMessage!, textAlign: TextAlign.center, style: TextStyle(color: MX.mute, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final Track track;
  final bool current;
  final bool bound;
  final VoidCallback? onTap;
  const _SourceRow({required this.track, required this.current, required this.bound, this.onTap});

  String get _subtitle => [track.artistText, track.album ?? ''].where((s) => s.isNotEmpty).join(' · ');

  String get _detail {
    final tags = <String>[];
    void add(String s) {
      if (s.isEmpty || (tags.isNotEmpty && tags.last == s)) return;
      tags.add(s);
    }

    add(MX.label(track.platform));
    add(SourcePick.qualityLabel(track));
    add(SourcePick.status(track, bound: bound));
    if (track.vip == true) add('VIP');
    if (track.trial == true) add('试听');
    return tags.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CoverArt(src: track.cover, size: 48, corner: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: current ? MX.ember : MX.fg, fontSize: 15)),
                  if (_subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(_subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MX.mute, fontSize: 12)),
                  ],
                  const SizedBox(height: 2),
                  Text(_detail,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MX.dimSoft, fontSize: 11)),
                ],
              ),
            ),
            if (current) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, size: 18, color: MX.ember),
            ],
          ],
        ),
      ),
    );
  }
}

// __APPEND_PICKER_SHEET__

/// 加入歌单 — pick a target playlist to add the selected track to.
class PlaylistPickerSheet extends StatefulWidget {
  const PlaylistPickerSheet({super.key});
  @override
  State<PlaylistPickerSheet> createState() => _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends State<PlaylistPickerSheet> {
  List<Playlist> _lists = [];
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<SessionStore>().api;
    try {
      final box = await api.getJson('/api/my/playlists', PlaylistsPayload.fromJson);
      if (!mounted) return;
      setState(() {
        _lists = (box.playlists ?? [])
            .where((p) => p.kind != 'favorites' && p.listKind != 'favorites')
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(Playlist p) async {
    if (_adding) return;
    final ui = context.read<UIStore>();
    final player = context.read<PlayerStore>();
    final t = ui.pickerTrack;
    if (t == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _adding = true);
    try {
      await player.addToPlaylist(p.id, t);
      if (!mounted) return;
      ui.notify('已加入「${p.displayTitle}」');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        setState(() => _adding = false);
        ui.notify('$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _SheetControllerScope.of(context);
    final ui = context.watch<UIStore>();
    final head = ui.pickerTrack;

    Widget body;
    if (_loading) {
      body = ListView(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (int i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SkeletonBar(height: 44),
            ),
        ],
      );
    } else if (_lists.isEmpty) {
      body = Center(child: Text('暂无可用歌单', style: TextStyle(color: MX.mute, fontSize: 14)));
    } else {
      body = ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _lists.length,
        itemBuilder: (context, i) {
          final p = _lists[i];
          return InkWell(
            onTap: _adding ? null : () => _add(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CoverArt(src: p.cover, mosaic: p.artTiles, size: 44, corner: 6),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: MX.fg, fontSize: 15)),
                        if (p.trackCount != null) ...[
                          const SizedBox(height: 2),
                          Text('${p.trackCount} 首',
                              style: TextStyle(color: MX.mute, fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.add, size: 18, color: MX.dimSoft),
                ],
              ),
            ),
          );
        },
      );
    }

    return _sheetFrame(
      title: head != null ? '加入歌单 · ${head.title}' : '加入歌单',
      controller: controller,
      body: body,
    );
  }
}



