import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/source_management.dart';
import '../models/models.dart';
import '../stores/session_store.dart';
import '../theme/theme.dart';
import 'ingest_records_view.dart';

String _pc(String v) => Uri.encodeComponent(v);

// ---------------------------------------------------------------------------
// SourceRunsView — 音源整理记录 list
// ---------------------------------------------------------------------------

class SourceRunsView extends StatefulWidget {
  const SourceRunsView({super.key});
  @override
  State<SourceRunsView> createState() => _SourceRunsViewState();
}

class _SourceRunsViewState extends State<SourceRunsView> {
  List<SourceSubstitutionRun> _runs = [];
  String? _error;
  bool _loading = false;
  String? _nextCursor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final session = context.read<SessionStore>();
    try {
      final suffix = more && _nextCursor != null ? '&cursor=${_pc(_nextCursor!)}' : '';
      final resp = await session.api
          .getJson('/api/source-substitution/runs?limit=30$suffix', SourceRunsResponse.fromJson);
      if (more) {
        final existing = _runs.map((r) => r.id).toSet();
        _runs = [..._runs, ...resp.items.where((r) => !existing.contains(r.id))];
      } else {
        _runs = resp.items;
      }
      _nextCursor = resp.nextCursor;
      _error = null;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MX.ink,
      appBar: AppBar(
        backgroundColor: MX.ink,
        surfaceTintColor: Colors.transparent,
        title: Text('音源整理记录', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        color: MX.ember,
        onRefresh: () => _load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
          children: [
            for (final run in _runs) _runRow(run),
            if (_error != null) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
              Center(child: OutlinedButton(onPressed: () => _load(), child: const Text('重试'))),
            ] else if (_runs.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 80),
                child: Column(
                  children: [
                    Icon(Icons.graphic_eq, color: MX.dim, size: 46),
                    const SizedBox(height: 12),
                    Text('暂无整理记录', style: TextStyle(color: MX.dim, fontSize: 15)),
                  ],
                ),
              ),
            if (_nextCursor != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: TextButton(
                    onPressed: _loading ? null : () => _load(more: true),
                    child: Text('加载更多', style: TextStyle(color: MX.ember)),
                  ),
                ),
              ),
            if (_loading) Center(child: Padding(padding: const EdgeInsets.all(16), child: CircularProgressIndicator(color: MX.ember))),
          ],
        ),
      ),
    );
  }

  Widget _runRow(SourceSubstitutionRun run) => InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SourceOrganizationView(run: run),
        )),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: MX.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: MX.hairline, width: 0.5)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('整理 ${run.total ?? 0} 首 · ${run.status}',
                        style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 3),
                    Text(run.backgroundIngest == true ? '后台入库已启用（独立进度）' : '仅整理，不下载',
                        style: TextStyle(color: MX.dim, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: MX.mute),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// SourceOrganizationView — 整理音源 (start or monitor a run)
// ---------------------------------------------------------------------------

class SourceOrganizationView extends StatefulWidget {
  final List<Track> tracks;
  final SourceSubstitutionRun? run;
  const SourceOrganizationView({super.key, this.tracks = const [], this.run});
  @override
  State<SourceOrganizationView> createState() => _SourceOrganizationViewState();
}

class _SourceOrganizationViewState extends State<SourceOrganizationView> {
  late bool _backgroundIngest = widget.run?.backgroundIngest ?? false;
  SourceSubstitutionRun? _run;
  bool _busy = false;
  String? _error;
  final _requestId = DateTime.now().microsecondsSinceEpoch.toString();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _run = widget.run;
    if (_run != null) _schedulePoll();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _poll?.cancel();
    final run = _run;
    if (run == null || run.isFinished) return;
    _poll = Timer(const Duration(milliseconds: 1500), _refreshStatus);
  }

  Future<void> _refreshStatus() async {
    final run = _run;
    if (run == null) return;
    final session = context.read<SessionStore>();
    try {
      final updated = await session.api
          .getJson('/api/source-substitution/runs/${_pc(run.id)}', SourceSubstitutionRun.fromJson);
      if (mounted) setState(() { _run = updated; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    _schedulePoll();
  }

  Future<void> _start() async {
    if (_busy || widget.tracks.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    final session = context.read<SessionStore>();
    try {
      _run = await session.api.organizeSources(
          tracks: widget.tracks, backgroundIngest: _backgroundIngest, requestId: _requestId);
      _schedulePoll();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _retry() async {
    final run = _run;
    if (run == null || _busy) return;
    setState(() => _busy = true);
    final session = context.read<SessionStore>();
    try {
      final body = <String, dynamic>{'action': 'retry'};
      if (run.version != null) body['version'] = run.version;
      final resp = await session.api.postJson(
          '/api/source-substitution/runs/${_pc(run.id)}/action', SourceRunActionResponse.fromJson,
          json: body);
      if (resp.ok) {
        await _refreshStatus();
      } else {
        _error = '状态已变化，请刷新后重试';
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    return Scaffold(
      backgroundColor: MX.ink,
      appBar: AppBar(
        backgroundColor: MX.ink,
        surfaceTintColor: Colors.transparent,
        title: Text('整理音源', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _overview(run),
          const SizedBox(height: 20),
          if (run != null) ...[
            _progressCard(run),
            if (run.backgroundIngest == true) ...[
              const SizedBox(height: 16),
              _ingestionCard(run),
            ],
            if ((run.items ?? []).any((i) => i.error != null)) ...[
              const SizedBox(height: 16),
              _failuresCard(run.items!.where((i) => i.error != null).toList()),
            ],
          ] else
            _preparationCard(),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _notice('暂时无法更新', _error!, Icons.warning_amber, Colors.orange),
          ],
        ],
      ),
      bottomNavigationBar: _actionBar(run),
    );
  }

  Widget _overview(SourceSubstitutionRun? run) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: MX.ember.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.graphic_eq, color: MX.ember),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(run == null ? '为歌曲找到可用音源' : '${(run.total ?? widget.tracks.length).clamp(0, 1 << 30)} 首歌曲',
                    style: TextStyle(color: MX.fg, fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                    run == null
                        ? '保留歌曲信息，优先使用本地文件，再寻找完整的在线音源。'
                        : '歌曲信息保持不变，整理进度会在这里自动更新。',
                    style: TextStyle(color: MX.dim, fontSize: 14)),
              ],
            ),
          ),
        ],
      );

  Widget _preparationCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.queue_music, size: 18, color: MX.fg),
                const SizedBox(width: 8),
                Text('已选择 ${widget.tracks.length} 首歌曲',
                    style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('同时存入音乐库', style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('整理成功后，在后台下载最高可用完整音质。', style: TextStyle(color: MX.dim, fontSize: 12)),
                    ],
                  ),
                ),
                Switch(
                  value: _backgroundIngest,
                  activeColor: MX.ember,
                  onChanged: _busy ? null : (v) => setState(() => _backgroundIngest = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_backgroundIngest ? '整理和下载独立进行，下载失败不会撤销整理结果。' : '本次只整理音源，不下载歌曲。',
                style: TextStyle(color: MX.dim, fontSize: 12)),
          ],
        ),
      );

  Widget _progressCard(SourceSubstitutionRun run) {
    final total = (run.total ?? widget.tracks.length).clamp(0, 1 << 30);
    final completed = (run.completed ?? 0).clamp(0, total);
    final pct = total > 0 ? (completed / total * 100).round() : 0;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: MX.fg),
              const SizedBox(width: 8),
              Text('整理进度', style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              _statusChip(run.status),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$completed', style: TextStyle(color: MX.fg, fontSize: 30, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('/ $total 首', style: TextStyle(color: MX.dim, fontSize: 14)),
              const Spacer(),
              Text(total > 0 ? '$pct%' : '—', style: TextStyle(color: MX.dim, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? completed / total : 0,
              backgroundColor: MX.hairline,
              color: MX.ember,
              minHeight: 6,
            ),
          ),
          const Divider(height: 28),
          Row(
            children: [
              _metric('已处理', completed, Icons.check_circle, MX.fg),
              _metric('未完成', (total - completed).clamp(0, 1 << 30), Icons.schedule, MX.dim),
              _metric('失败', (run.failed ?? 0).clamp(0, 1 << 30), Icons.error_outline,
                  (run.failed ?? 0) > 0 ? Colors.orange : MX.dim),
            ],
          ),
          const SizedBox(height: 12),
          Text(run.isFinished ? '本次整理已结束。音源状态以各首歌曲的处理结果为准。' : '正在按顺序处理歌曲，平台繁忙时会自动等待。',
              style: TextStyle(color: MX.dim, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _ingestionCard(SourceSubstitutionRun run) {
    final ing = run.ingestion;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.download, size: 18, color: MX.fg),
              const SizedBox(width: 8),
              Text('后台入库', style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('独立进行', style: TextStyle(color: MX.dim, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          if (ing != null)
            Wrap(
              spacing: 24,
              runSpacing: 14,
              children: [
                _metricInline('排队中', ing.queued, Icons.schedule, MX.dim),
                _metricInline('下载中', ing.running, Icons.arrow_downward, MX.fg),
                _metricInline('已入库', ing.completed, Icons.check_circle, MX.fg),
                _metricInline('失败', ing.failed, Icons.error_outline, ing.failed > 0 ? Colors.orange : MX.dim),
              ],
            )
          else
            Text('整理成功的歌曲会陆续加入下载队列。', style: TextStyle(color: MX.dim, fontSize: 14)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IngestRecordsView())),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('查看入库记录'),
          ),
          const SizedBox(height: 8),
          Text('下载进度不计入上方的整理进度。', style: TextStyle(color: MX.dim, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _failuresCard(List<SourceRunItem> items) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Text('需要关注', style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < items.length; i++) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(items[i].title ?? '未命名歌曲', style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(items[i].error ?? '整理失败', style: TextStyle(color: MX.dim, fontSize: 12)),
                ],
              ),
              if (i < items.length - 1) const Divider(height: 20),
            ],
          ],
        ),
      );

  Widget _notice(String title, String detail, IconData icon, Color color) => _card(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(detail, style: TextStyle(color: MX.dim, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _actionBar(SourceSubstitutionRun? run) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(color: MX.panel, border: Border(top: BorderSide(color: MX.hairline, width: 0.5))),
        child: Row(
          children: [
            Expanded(
              child: Text(run == null ? '准备好后开始整理' : '关闭后，后台任务仍会保留',
                  style: TextStyle(color: MX.dim, fontSize: 12)),
            ),
            const SizedBox(width: 12),
            if (run != null) ...[
              if (run.canRetry)
                FilledButton(
                  onPressed: _busy ? null : _retry,
                  style: FilledButton.styleFrom(backgroundColor: MX.ember),
                  child: Text(_busy ? '提交中…' : '重试失败项'),
                )
              else
                OutlinedButton.icon(
                  onPressed: _busy ? null : _refreshStatus,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新状态'),
                ),
            ] else
              FilledButton(
                onPressed: (_busy || widget.tracks.isEmpty) ? null : _start,
                style: FilledButton.styleFrom(backgroundColor: MX.ember),
                child: Text(_busy ? '正在提交…' : (_error == null ? '开始整理' : '重试提交')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: MX.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: MX.hairline, width: 0.5)),
        child: child,
      );

  Widget _metric(String title, int value, IconData icon, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
                Text(title, style: TextStyle(color: color, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            Text('$value', style: TextStyle(color: MX.fg, fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _metricInline(String title, int value, IconData icon, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(title, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Text('$value', style: TextStyle(color: MX.fg, fontSize: 18, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _statusChip(String status) {
    String label;
    switch (status) {
      case 'queued':
      case 'pending':
        label = '排队中';
        break;
      case 'running':
      case 'checking':
      case 'processing':
        label = '整理中';
        break;
      case 'retry_wait':
      case 'waiting':
      case 'deferred':
        label = '等待重试';
        break;
      case 'pending_match':
      case 'needs_confirmation':
        label = '待确认';
        break;
      case 'completed':
      case 'done':
        label = '已完成';
        break;
      case 'partial':
      case 'completed_with_errors':
        label = '部分完成';
        break;
      case 'failed':
      case 'error':
        label = '整理失败';
        break;
      case 'cancelled':
        label = '已取消';
        break;
      case 'paused':
        label = '已暂停';
        break;
      default:
        label = '等待更新';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: MX.hairline, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: MX.fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
