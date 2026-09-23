import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';

String _enc(String s) => Uri.encodeComponent(s);

/// 文件浏览 — compact (phone) Finder-style browser. Mirrors the iOS compact
/// branch of Swift `LocalFilesView`: a navigation stack of directory listings.
class LocalFilesView extends StatefulWidget {
  final String path;
  const LocalFilesView({super.key, required this.path});
  @override
  State<LocalFilesView> createState() => _LocalFilesViewState();
}

class _LocalFilesViewState extends State<LocalFilesView> {
  LibraryBrowse? _browse;
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  List<LibraryEntry> get _visible {
    final all = _browse?.entries ?? [];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((e) =>
        e.name.toLowerCase().contains(q) ||
        (e.title ?? '').toLowerCase().contains(q) ||
        (e.artists ?? []).any((a) => a.toLowerCase().contains(q))).toList();
  }

  List<LibraryEntry> get _audios =>
      (_browse?.entries ?? []).where((e) => e.audio == true && e.track != null).toList();

  String get _title {
    final t = _browse?.title;
    if (t != null && t.isNotEmpty) return t;
    return _pathTitle(widget.path);
  }

  Future<void> _load() async {
    setState(() => _loading = _browse == null);
    final session = context.read<SessionStore>();
    final url = '/api/library/browse?path=${_enc(widget.path)}';
    try {
      _browse = await session.api.getJson(url, LibraryBrowse.fromJson);
      _error = null;
    } catch (e) {
      if (_browse == null) _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _play(Track track) {
    final player = context.read<PlayerStore>();
    final queue = _audios.map((e) => e.track!).toList();
    final idx = queue.indexWhere((t) => t.key == track.key);
    if (idx >= 0) {
      player.replaceQueue(queue, start: idx);
    } else {
      player.playNow(track);
    }
  }

  void _playAll() {
    final queue = _audios.map((e) => e.track!).toList();
    if (queue.isEmpty) return;
    context.read<PlayerStore>().replaceQueue(queue, start: 0);
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.read<UIStore>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(_title, style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
        actions: [
          if (_audios.isNotEmpty)
            IconButton(
              onPressed: _playAll,
              icon: Icon(Icons.play_arrow, color: MX.ember),
              tooltip: '播放全部',
            ),
        ],
      ),
      body: RefreshIndicator(
        color: MX.ember,
        onRefresh: _load,
        child: _error != null && _browse == null
            ? _errorView()
            : (!_loading && _visible.isEmpty)
                ? _emptyView()
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          style: TextStyle(color: MX.fg),
                          decoration: InputDecoration(
                            hintText: '搜索此目录',
                            hintStyle: TextStyle(color: MX.mute),
                            prefixIcon: Icon(Icons.search, color: MX.mute),
                            filled: true,
                            fillColor: MX.panel,
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                              12, 4, 12, MediaQuery.paddingOf(context).bottom),
                          itemCount: _visible.length,
                          itemBuilder: (_, i) => _row(_visible[i], ui),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _row(LibraryEntry entry, UIStore ui) {
    if (entry.type == 'dir') {
      return InkWell(
        onTap: () => ui.open(LocalFolderRoute(entry.path)),
        child: _folderRow(entry),
      );
    } else if (entry.audio == true && entry.track != null) {
      return InkWell(
        onTap: () => _play(entry.track!),
        child: _audioRow(entry, entry.track!),
      );
    }
    return _unknownRow(entry);
  }

  Widget _folderRow(LibraryEntry entry) {
    final root = widget.path.isEmpty;
    final title = root ? _rootName(entry.name) : (entry.title?.isNotEmpty == true && entry.title != entry.name ? entry.title! : entry.name);
    final subtitle = root
        ? (entry.name == 'files' ? '手动上传与导入' : '已入库音源')
        : ((entry.artists ?? []).isEmpty ? '文件夹' : entry.artists!.join(' / '));
    final tint = root ? MX.tone(entry.name) : const Color(0xE6E5C33B);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          if (entry.artworkUrl?.isNotEmpty ?? false)
            CoverArt(src: entry.artworkUrl, size: 44, corner: 8)
          else
            _glyph(Icons.folder, tint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MX.fg)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MX.dim, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: MX.mute),
        ],
      ),
    );
  }

  Widget _audioRow(LibraryEntry entry, Track track) {
    final player = context.watch<PlayerStore>();
    final current = player.track?.key == track.key;
    final album = (track.album ?? entry.album ?? '').trim();
    final singer = track.artistText.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          CoverArt(src: track.cover ?? entry.artworkUrl, size: 44, corner: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: current ? MX.ember : MX.fg)),
                if (album.isNotEmpty || singer.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        if (album.isNotEmpty) _metaTag('专辑', album, Icons.library_music),
                        if (singer.isNotEmpty) _metaTag('歌手', singer, Icons.person),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(_fileInfo(entry),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MX.mute, fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if ((track.durationMs ?? 0) > 0)
            Text(_fmt((track.durationMs! / 1000).round()),
                style: TextStyle(color: MX.mute, fontSize: 12))
          else if ((entry.size ?? 0) > 0)
            Text(_bytes(entry.size), style: TextStyle(color: MX.mute, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _unknownRow(LibraryEntry entry) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            _glyph(Icons.insert_drive_file, MX.mute),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MX.dim)),
                  Text(_bytes(entry.size), style: TextStyle(color: MX.mute, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _metaTag(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: MX.mute.withOpacity(0.13), borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: MX.dim),
            const SizedBox(width: 3),
            Text('$label $value',
                style: TextStyle(color: MX.dim, fontSize: 10, fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Widget _glyph(IconData icon, Color tint) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: tint.withOpacity(0.18), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: tint),
      );

  Widget _errorView() => ListView(
        children: [
          const SizedBox(height: 90),
          Icon(Icons.folder_off, color: MX.dim, size: 46),
          const SizedBox(height: 12),
          Center(child: Text('无法打开', style: TextStyle(color: MX.fg, fontSize: 17, fontWeight: FontWeight.w600))),
          const SizedBox(height: 6),
          Center(child: Text(_error ?? '', style: TextStyle(color: MX.dim, fontSize: 13))),
          const SizedBox(height: 14),
          Center(child: OutlinedButton(onPressed: _load, child: const Text('重试'))),
        ],
      );

  Widget _emptyView() => ListView(
        children: [
          const SizedBox(height: 90),
          Icon(Icons.folder_open, color: MX.dim, size: 46),
          const SizedBox(height: 12),
          Center(
              child: Text(_query.isEmpty ? '空目录' : '没有匹配项',
                  style: TextStyle(color: MX.fg, fontSize: 17, fontWeight: FontWeight.w600))),
        ],
      );

  String _fileInfo(LibraryEntry entry) {
    final parts = <String>[];
    final added = _addedAt(entry.createdAt);
    if (added != null) parts.add('入库 $added');
    if (entry.ext?.isNotEmpty ?? false) parts.add(entry.ext!.toUpperCase());
    if (parts.isEmpty) parts.add('本地音频');
    return parts.join(' · ');
  }
}

String _pathTitle(String path) {
  if (path.isEmpty) return '文件浏览';
  final last = path.split('/').where((s) => s.isNotEmpty).isEmpty
      ? path
      : path.split('/').lastWhere((s) => s.isNotEmpty);
  return path.contains('/') ? last : _rootName(last);
}

String _rootName(String name) {
  final label = MX.label(name);
  return label.isEmpty ? name : label;
}

String? _addedAt(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  final l = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}/${two(l.month)}/${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String _bytes(double? value) {
  final v = value ?? 0;
  if (v <= 0) return '—';
  if (v < 1024) return '${v.round()} B';
  if (v < 1024 * 1024) return '${(v / 1024).toStringAsFixed(1)} KB';
  if (v < 1024 * 1024 * 1024) return '${(v / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(v / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String _fmt(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
