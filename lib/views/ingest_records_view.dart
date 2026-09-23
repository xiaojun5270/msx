import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/theme.dart';
import 'components.dart';

String _enc(String s) => Uri.encodeComponent(s);

/// 媒体入库记录 — mirrors Swift `IngestRecordsView`.
class IngestRecordsView extends StatefulWidget {
  const IngestRecordsView({super.key});
  @override
  State<IngestRecordsView> createState() => _IngestRecordsViewState();
}

class _IngestRecordsViewState extends State<IngestRecordsView> {
  static const _pageSize = 40;
  static const _statusOptions = [
    ('all', '全部状态'),
    ('active', '进行中'),
    ('error', '失败'),
    ('done', '已完成'),
  ];

  List<IngestJob> _jobs = [];
  int _total = 0;
  final Set<String> _retrying = {};
  bool _loading = true;
  String _query = '';
  String _debounced = '';
  int _limit = _pageSize;
  String _platform = 'all';
  String _status = 'all';
  Timer? _debounce;
  Timer? _poll;
  final _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startWatch());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  List<String> get _ingestPlatforms {
    final session = context.read<SessionStore>();
    final set = <String>{
      ..._jobs.map((j) => j.platform ?? '').where((p) => p.isNotEmpty),
      ...session.bindings.keys,
      if (_platform != 'all') _platform,
    }..removeWhere((p) => p.isEmpty);
    return set.toList()..sort();
  }

  List<IngestJob> get _filtered => _jobs.where((job) {
        if (_platform != 'all' && (job.platform ?? '') != _platform) return false;
        switch (_status) {
          case 'all':
            return true;
          case 'active':
            return job.status == 'queued' || job.status == 'running';
          default:
            return job.status == _status;
        }
      }).toList();

  List<IngestJob> get _active =>
      _filtered.where((j) => j.status == 'queued' || j.status == 'running').toList();

  List<IngestJob> get _sorted {
    final list = [..._filtered];
    list.sort((a, b) =>
        (b.createdAt ?? b.updatedAt ?? '').compareTo(a.createdAt ?? a.updatedAt ?? ''));
    return list;
  }

  bool get _hasMore => _jobs.isNotEmpty && _jobs.length < _total;
  bool get _filterActive => _platform != 'all' || _status != 'all';

  String get _emptyHint {
    final parts = <String>[];
    if (_platform != 'all') parts.add(MX.label(_platform));
    final st = _statusOptions.firstWhere((o) => o.$1 == _status, orElse: () => ('', ''));
    if (_status != 'all' && st.$2.isNotEmpty) parts.add(st.$2);
    if (_debounced.isNotEmpty) parts.add('“$_debounced”');
    return parts.isEmpty ? '试试调整筛选条件' : parts.join(' · ');
  }

  void _startWatch() {
    _refresh();
    _scheduleNext();
  }

  void _scheduleNext() {
    _poll?.cancel();
    final wait = _active.isEmpty ? const Duration(milliseconds: 2400) : const Duration(milliseconds: 800);
    _poll = Timer(wait, () async {
      if (!mounted) return;
      await _refresh();
      _scheduleNext();
    });
  }

  Future<void> _refresh() async {
    final session = context.read<SessionStore>();
    final items = <String>['limit=$_limit'];
    if (_debounced.isNotEmpty) items.add('q=${_enc(_debounced)}');
    if (_platform != 'all') items.add('platform=${_enc(_platform)}');
    if (_status != 'all' && _status != 'active') items.add('status=${_enc(_status)}');
    final url = '/api/library/jobs?${items.join('&')}';
    try {
      final box = await session.api.getJson(url, IngestJobsBox.fromJson);
      _jobs = box.items ?? [];
      _total = box.total ?? _jobs.length;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final trimmed = v.trim();
      if (trimmed != _debounced) {
        _debounced = trimmed;
        _limit = _pageSize;
        _refresh();
      }
    });
  }

  void _loadMore() {
    setState(() => _limit = (_limit + _pageSize).clamp(0, 200));
    _refresh();
  }

  Future<void> _retry(IngestJob job) async {
    setState(() => _retrying.add(job.id));
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      final next = await session.api.postJson('/api/library/jobs/${_enc(job.id)}/retry', IngestJob.fromJson);
      _jobs = _jobs.map((j) => j.id == job.id ? next : j).toList();
      final resumed = (next.bytesReceived ?? job.bytesReceived ?? 0) > 0;
      ui.notify(resumed ? '已继续下载' : '已重新开始');
      await _refresh();
    } catch (e) {
      ui.notify('$e');
    }
    if (mounted) setState(() => _retrying.remove(job.id));
  }

  void _playJob(IngestJob job) {
    if (job.status != 'done' || job.file == null) return;
    context.read<PlayerStore>().replaceQueue([job.file!.asTrack()], start: 0);
  }

  Future<void> _openReplacement(IngestJob job) async {
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    final next = await showModalBottomSheet<IngestJob>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MX.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReplacementSheet(job: job, api: session.api),
    );
    if (next != null) {
      _jobs = _jobs.map((j) => j.id == next.id ? next : j).toList();
      ui.notify('已使用所选音源重新加入队列');
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text('媒体入库记录', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
        actions: [_filterMenu()],
      ),
      body: RefreshIndicator(
        color: MX.ember,
        onRefresh: _refresh,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _searchCtl,
                onChanged: _onQueryChanged,
                style: TextStyle(color: MX.fg),
                decoration: InputDecoration(
                  hintText: '搜索标题、ID…',
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
              child: (!_loading && _filtered.isEmpty)
                  ? _emptyView()
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                          12, 6, 12, MediaQuery.paddingOf(context).bottom),
                      itemCount: sorted.length + 2,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                            child: Text('共 $_total 条', style: TextStyle(color: MX.dim, fontSize: 13)),
                          );
                        }
                        if (i == sorted.length + 1) {
                          if (!_hasMore) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: TextButton(
                                onPressed: _loading ? null : _loadMore,
                                child: Text(_loading ? '加载中…' : '加载更多',
                                    style: TextStyle(color: MX.ember)),
                              ),
                            ),
                          );
                        }
                        return _IngestJobRow(
                          job: sorted[i - 1],
                          retrying: _retrying.contains(sorted[i - 1].id),
                          onRetry: () => _retry(sorted[i - 1]),
                          onReplace: sorted[i - 1].replacementSuggestion == null
                              ? null
                              : () => _openReplacement(sorted[i - 1]),
                          onPlay: () => _playJob(sorted[i - 1]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterMenu() => PopupMenuButton<String>(
        icon: Icon(_filterActive ? Icons.filter_alt : Icons.filter_alt_outlined, color: MX.fg),
        color: MX.panel,
        onSelected: (v) {
          setState(() {
            if (v.startsWith('p:')) {
              _platform = v.substring(2);
            } else if (v.startsWith('s:')) {
              _status = v.substring(2);
            }
            _limit = _pageSize;
          });
          _refresh();
        },
        itemBuilder: (_) => [
          PopupMenuItem(enabled: false, child: Text('平台', style: TextStyle(color: MX.dim, fontSize: 12))),
          PopupMenuItem(value: 'p:all', child: _menuLabel('全部平台', _platform == 'all')),
          for (final id in _ingestPlatforms)
            PopupMenuItem(value: 'p:$id', child: _menuLabel(MX.label(id), _platform == id)),
          const PopupMenuDivider(),
          PopupMenuItem(enabled: false, child: Text('状态', style: TextStyle(color: MX.dim, fontSize: 12))),
          for (final opt in _statusOptions)
            PopupMenuItem(value: 's:${opt.$1}', child: _menuLabel(opt.$2, _status == opt.$1)),
        ],
      );

  Widget _menuLabel(String text, bool selected) => Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(color: MX.fg))),
          if (selected) Icon(Icons.check, size: 16, color: MX.ember),
        ],
      );

  Widget _emptyView() => ListView(
        children: [
          const SizedBox(height: 80),
          Icon(_filterActive ? Icons.filter_alt_off : Icons.inbox, color: MX.dim, size: 46),
          const SizedBox(height: 12),
          Center(child: Text('暂无记录', style: TextStyle(color: MX.fg, fontSize: 17, fontWeight: FontWeight.w600))),
          const SizedBox(height: 6),
          Center(child: Text(_emptyHint, style: TextStyle(color: MX.dim, fontSize: 13))),
        ],
      );
}

class _IngestJobRow extends StatelessWidget {
  final IngestJob job;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback? onReplace;
  final VoidCallback onPlay;
  const _IngestJobRow({
    required this.job,
    required this.retrying,
    required this.onRetry,
    required this.onReplace,
    required this.onPlay,
  });

  bool get _busy => job.status == 'queued' || job.status == 'running';
  String? get _cover => job.file?.artworkUrl ?? job.artworkUrl;
  String get _title => job.title ?? job.sourceId ?? '任务';
  String get _percentText => job.percent != null ? '${job.percent!.round()}%' : '…';

  String get _subtitle {
    final parts = <String>[MX.label(job.platform ?? '')];
    if (job.artists?.isNotEmpty ?? false) parts.add(job.artists!.join(' / '));
    final q = job.quality;
    if (q != null && q.isNotEmpty && q != 'default' && q != 'bestaudio') parts.add(q);
    return parts.where((p) => p.isNotEmpty).join(' · ');
  }

  void _tap() {
    switch (job.status) {
      case 'error':
        (onReplace ?? onRetry)();
        break;
      case 'done':
        onPlay();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerStore>();
    return InkWell(
      onTap: _tap,
      onLongPress: () => _showMenu(context, player),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CoverArt(src: _cover, size: 56, corner: 8),
                _statusIcon(),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(_title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(width: 8),
                      _statusMark(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MX.dim, fontSize: 12)),
                  if (_busy) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ((job.percent ?? 0) / 100).clamp(0, 1),
                        backgroundColor: MX.hairline,
                        color: MX.ember,
                        minHeight: 3,
                      ),
                    ),
                  ],
                  if (job.replacementSuggestion != null && job.status == 'error') ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.swap_horiz, size: 13, color: MX.ember),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('已找到 ${job.replacementSuggestion!.candidates.length} 个严格匹配音源',
                              style: TextStyle(color: MX.ember, fontSize: 11)),
                        ),
                        TextButton(
                          onPressed: onReplace,
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
                          child: Text('替换入库', style: TextStyle(color: MX.ember, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                  if ((job.error?.isNotEmpty ?? false) && job.status == 'error') ...[
                    const SizedBox(height: 3),
                    Text(job.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: job.replacementSuggestion == null
                                ? Colors.red.withOpacity(0.9)
                                : MX.dim,
                            fontSize: 11)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon() {
    switch (job.status) {
      case 'done':
        return Container(
          decoration: BoxDecoration(color: MX.ember, shape: BoxShape.circle),
          child: const Icon(Icons.play_arrow, size: 14, color: Colors.white),
        );
      case 'running':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(8)),
          child: Text(_percentText,
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        );
      case 'error':
        return const Icon(Icons.warning, size: 14, color: Colors.red);
      case 'queued':
        return Icon(Icons.schedule, size: 13, color: MX.dim);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _statusMark() {
    switch (job.status) {
      case 'queued':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: MX.hairline, borderRadius: BorderRadius.circular(10)),
          child: Text('排队', style: TextStyle(color: MX.dim, fontSize: 11, fontWeight: FontWeight.w600)),
        );
      case 'running':
        return Text(_percentText,
            style: TextStyle(color: MX.ember, fontSize: 13, fontWeight: FontWeight.w600));
      case 'done':
        return Icon(Icons.check_circle, size: 18, color: Colors.green.withOpacity(0.85));
      case 'error':
        if (onReplace != null) {
          return TextButton(
            onPressed: onReplace,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
            child: Text('替换入库', style: TextStyle(color: MX.ember, fontSize: 13, fontWeight: FontWeight.w600)),
          );
        }
        return TextButton(
          onPressed: retrying ? null : onRetry,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
          child: Text(retrying ? '重试中' : '重试', style: TextStyle(color: MX.ember, fontSize: 13, fontWeight: FontWeight.w600)),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _showMenu(BuildContext context, PlayerStore player) {
    final file = job.file;
    showModalBottomSheet(
      context: context,
      backgroundColor: MX.panel,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (job.status == 'error') ...[
              if (onReplace != null)
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: MX.fg),
                  title: Text('替换入库', style: TextStyle(color: MX.fg)),
                  onTap: () { Navigator.pop(context); onReplace!(); },
                ),
              ListTile(
                leading: Icon(Icons.refresh, color: MX.fg),
                title: Text('重试', style: TextStyle(color: MX.fg)),
                onTap: () { Navigator.pop(context); onRetry(); },
              ),
            ],
            if (file != null) ...[
              ListTile(
                leading: Icon(Icons.play_arrow, color: MX.fg),
                title: Text('播放', style: TextStyle(color: MX.fg)),
                onTap: () { Navigator.pop(context); onPlay(); },
              ),
              ListTile(
                leading: Icon(Icons.playlist_play, color: MX.fg),
                title: Text('下一首播放', style: TextStyle(color: MX.fg)),
                onTap: () { Navigator.pop(context); player.playNext(file.asTrack()); },
              ),
              ListTile(
                leading: Icon(Icons.playlist_add, color: MX.fg),
                title: Text('加入队列', style: TextStyle(color: MX.fg)),
                onTap: () { Navigator.pop(context); player.enqueue(file.asTrack()); },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReplacementSheet extends StatefulWidget {
  final IngestJob job;
  final dynamic api;
  const _ReplacementSheet({required this.job, required this.api});
  @override
  State<_ReplacementSheet> createState() => _ReplacementSheetState();
}

class _ReplacementSheetState extends State<_ReplacementSheet> {
  String? _submittingKey;
  String? _error;

  List<IngestReplacementCandidate> get _candidates =>
      widget.job.replacementSuggestion?.candidates ?? [];

  Future<void> _replace(IngestReplacementCandidate c) async {
    if (_submittingKey != null) return;
    setState(() {
      _submittingKey = c.key;
      _error = null;
    });
    try {
      final next = await widget.api.postJson(
        '/api/library/jobs/${_enc(widget.job.id)}/replace-source',
        IngestJob.fromJson,
        json: {
          'candidate': {'platform': c.platform, 'id': c.id}
        },
      );
      if (mounted) Navigator.pop(context, next);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _submittingKey = null);
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: MX.hairline, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text(job.title ?? job.sourceId ?? '歌曲',
              style: TextStyle(color: MX.fg, fontSize: 18, fontWeight: FontWeight.bold)),
          if (job.artists?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(job.artists!.join(' / '), style: TextStyle(color: MX.dim, fontSize: 14)),
            ),
          const SizedBox(height: 12),
          Text(job.replacementSuggestion?.message ?? '当前音源无法完整下载，请选择严格匹配的替代音源。',
              style: TextStyle(color: MX.dim, fontSize: 13)),
          const SizedBox(height: 18),
          Text('严格匹配音源 · 选择后重新入库',
              style: TextStyle(color: MX.dim, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(child: Text('暂无可替换音源', style: TextStyle(color: MX.dim))),
            )
          else
            for (final c in _candidates)
              InkWell(
                onTap: _submittingKey != null ? null : () => _replace(c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      CoverArt(src: c.artworkUrl, size: 48, corner: 8),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: MX.fg, fontSize: 14)),
                            Text(c.artists.join(' / '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: MX.dim, fontSize: 12)),
                            Text([MX.label(c.platform), c.album ?? '', c.quality ?? '']
                                .where((s) => s.isNotEmpty)
                                .join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: MX.mute, fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_submittingKey == c.key)
                        SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: MX.ember))
                      else
                        Icon(Icons.arrow_circle_right, color: MX.ember),
                    ],
                  ),
                ),
              ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
