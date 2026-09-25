import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'components.dart';

class _SyncResult {
  final bool ok;
  final int? added;
  final int? removed;
  final String? error;
  const _SyncResult({this.ok = false, this.added, this.removed, this.error});
  factory _SyncResult.fromJson(Map<String, dynamic> c) => _SyncResult(
        ok: (c['ok'] as bool?) ?? false,
        added: (c['added'] as num?)?.toInt(),
        removed: (c['removed'] as num?)?.toInt(),
        error: c['error'] as String?,
      );
}

String _relative(String? ts) {
  if (ts == null || ts.isEmpty) return '待同步';
  final date = DateTime.tryParse(ts);
  if (date == null) return '—';
  final diff = DateTime.now().difference(date.toLocal());
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 7) return '${diff.inDays}天前';
  final l = date.toLocal();
  return '${l.year}/${l.month}/${l.day}';
}

// ---------------------------------------------------------------------------
// SubscriptionsView — grid of subscription cards
// ---------------------------------------------------------------------------

class SubscriptionsView extends StatefulWidget {
  const SubscriptionsView({super.key});
  @override
  State<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends State<SubscriptionsView> {
  List<Subscription> _items = [];
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    if (_items.isEmpty) {
      final cached = session.peekPage('subscriptions.list', SubscriptionsBox.fromJson);
      if (cached != null) _items = cached.items ?? [];
    }
    if (mounted) setState(() => _loading = _items.isEmpty);
    final box = await session.fetchPage('/api/subscriptions',
        cacheKey: 'subscriptions.list', factory: SubscriptionsBox.fromJson);
    if (box != null) _items = box.items ?? [];
    if (mounted) setState(() => _loading = false);
  }

  void _openPlaylist(Subscription sub) {
    final kind = sub.kind == 'chart' ? ListKind.chart : ListKind.platform;
    context.read<UIStore>().open(
        PlaylistRoute(platform: sub.platform, id: sub.sourceId, kind: kind, fromLibrary: false));
  }

  Future<void> _run(Subscription sub, String task) async {
    if (_busyId != null) return;
    setState(() => _busyId = sub.id);
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      if (task == 'refresh') {
        final res = await session.api.postJson('/api/subscriptions/${sub.id}/sync', _SyncResult.fromJson);
        ui.notify(res.ok ? '同步完成 · +${res.added ?? 0} -${res.removed ?? 0}' : (res.error ?? '同步失败'));
      } else {
        await session.api.post('/api/subscriptions/${sub.id}/run', json: {'task': task});
        ui.notify('入库已触发');
      }
      await _load();
    } catch (e) {
      ui.notify('$e');
    }
    if (mounted) setState(() => _busyId = null);
  }

  Future<void> _remove(Subscription sub) async {
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      await session.api.delete('/api/subscriptions/${sub.id}');
      setState(() => _items.removeWhere((s) => s.id == sub.id));
      ui.notify('已取消订阅');
    } catch (e) {
      ui.notify('$e');
    }
  }

  void _confirmDelete(Subscription sub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('取消订阅', style: TextStyle(color: MX.fg)),
        content: Text('确定取消订阅「${sub.title}」？', style: TextStyle(color: MX.dim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消', style: TextStyle(color: MX.dim))),
          TextButton(
            onPressed: () { Navigator.pop(ctx); _remove(sub); },
            child: const Text('取消订阅', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings(Subscription sub) async {
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MX.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SettingsDrawer(sub: sub),
    );
    if (deleted == true) _confirmDelete(sub);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text('订阅', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        color: MX.ember,
        onRefresh: _load,
        child: (_loading && _items.isEmpty)
            ? Center(child: CircularProgressIndicator(color: MX.ember))
            : _items.isEmpty
                ? _empty()
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (_, i) => _SubscriptionCard(
                      sub: _items[i],
                      busy: _busyId == _items[i].id,
                      onTap: () => _openPlaylist(_items[i]),
                      onSync: () => _run(_items[i], 'refresh'),
                      onIngest: () => _run(_items[i], 'ingest'),
                      onSettings: () => _openSettings(_items[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _empty() => ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.notifications_none, color: MX.dim, size: 48),
          const SizedBox(height: 12),
          Center(child: Text('暂无订阅', style: TextStyle(color: MX.fg, fontSize: 18, fontWeight: FontWeight.w600))),
          const SizedBox(height: 6),
          Center(child: Text('打开任意平台歌单或榜单，点击「订阅」开始。', style: TextStyle(color: MX.dim, fontSize: 13))),
        ],
      );
}

class _SubscriptionCard extends StatelessWidget {
  final Subscription sub;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onSync;
  final VoidCallback onIngest;
  final VoidCallback onSettings;
  const _SubscriptionCard({
    required this.sub,
    required this.busy,
    required this.onTap,
    required this.onSync,
    required this.onIngest,
    required this.onSettings,
  });

  Color get _statusColor {
    switch (sub.lastRefreshStatus) {
      case 'ok':
        return Colors.green;
      case 'error':
        return Colors.red;
      default:
        return sub.refreshEnabled ? MX.ember : Colors.grey.withOpacity(0.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: MX.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MX.hairline, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(aspectRatio: 1, child: CoverArt(src: sub.coverUrl, corner: 0)),
                Positioned(
                  left: 8,
                  top: 8,
                  child: PlatformChip(id: sub.platform),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 5, height: 5, decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Icon(sub.kind == 'chart' ? Icons.bar_chart : Icons.queue_music, size: 11, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 38,
                    child: Text(sub.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MX.fg, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 4),
                  Text('${sub.kind == 'chart' ? '榜单' : '歌单'} · ${sub.trackCount} 首',
                      style: TextStyle(color: MX.dim, fontSize: 11)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.refresh, size: 11, color: MX.mute),
                      const SizedBox(width: 3),
                      Text(_relative(sub.lastRefreshAt), style: TextStyle(color: MX.mute, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  _pill('同步', Icons.refresh, busy ? null : onSync),
                  const SizedBox(width: 4),
                  _pill('入库', Icons.download, busy ? null : onIngest),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: onSettings,
                    icon: Icon(Icons.settings, size: 16, color: MX.dim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String title, IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: MX.hairline, borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: MX.fg),
              const SizedBox(width: 3),
              Text(title, style: TextStyle(color: MX.fg, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

class _SettingsDrawer extends StatefulWidget {
  final Subscription sub;
  const _SettingsDrawer({required this.sub});
  @override
  State<_SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<_SettingsDrawer> {
  late bool _refreshEnabled = widget.sub.refreshEnabled;
  late bool _ingestEnabled = widget.sub.ingestEnabled;
  late final _refreshCron = TextEditingController(text: widget.sub.refreshCron);
  late final _ingestCron = TextEditingController(text: widget.sub.ingestCron);
  bool _busy = false;

  @override
  void dispose() {
    _refreshCron.dispose();
    _ingestCron.dispose();
    super.dispose();
  }

  Future<void> _patch(Map<String, dynamic> changes) async {
    setState(() => _busy = true);
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      await session.api.put('/api/subscriptions/${widget.sub.id}', json: changes);
    } catch (e) {
      ui.notify('$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.sub;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: MX.hairline, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CoverArt(src: sub.coverUrl, size: 56, corner: 12),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${MX.label(sub.platform)} · ${sub.trackCount} 首',
                        style: TextStyle(color: MX.dim, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _cronCard('定时刷新', Icons.refresh, _refreshEnabled, _refreshCron, '0 */6 * * *',
              (v) { setState(() => _refreshEnabled = v); _patch({'refreshEnabled': v}); },
              () => _patch({'refreshCron': _refreshCron.text.trim()})),
          const SizedBox(height: 8),
          Text('按最高可用完整音质入库；失败可在入库记录中重试。',
              style: TextStyle(color: MX.dim, fontSize: 12)),
          const SizedBox(height: 8),
          _cronCard('定时入库', Icons.download, _ingestEnabled, _ingestCron, '30 3 * * *',
              (v) { setState(() => _ingestEnabled = v); _patch({'ingestEnabled': v}); },
              () => _patch({'ingestCron': _ingestCron.text.trim()})),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(44)),
            icon: const Icon(Icons.notifications_off, size: 18),
            label: const Text('取消订阅'),
          ),
        ],
      ),
    );
  }

  Widget _cronCard(String title, IconData icon, bool enabled, TextEditingController ctl,
      String hint, ValueChanged<bool> onToggle, VoidCallback onSubmitCron) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: MX.ink, borderRadius: BorderRadius.circular(16), border: Border.all(color: MX.hairline, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: MX.ember),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Switch(
                value: enabled,
                activeColor: MX.ember,
                onChanged: _busy ? null : onToggle,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Cron', style: TextStyle(color: MX.fg)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: ctl,
                    enabled: !_busy,
                    textAlign: TextAlign.right,
                    onSubmitted: (_) => onSubmitCron(),
                    style: TextStyle(color: MX.fg, fontFamily: 'monospace', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(color: MX.mute),
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SubscriptionDetailView
// ---------------------------------------------------------------------------

class SubscriptionDetailView extends StatefulWidget {
  final String subscriptionId;
  const SubscriptionDetailView({super.key, required this.subscriptionId});
  @override
  State<SubscriptionDetailView> createState() => _SubscriptionDetailViewState();
}

class _SubscriptionDetailViewState extends State<SubscriptionDetailView> {
  Subscription? _sub;
  SubscriptionStats? _stats;
  List<PlaylistChange> _changes = [];
  bool _busy = false;
  String _tab = 'tracks';
  bool _showOrphans = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  List<SubscriptionTrack> get _active => (_sub?.tracks ?? []).where((t) => t.status == 'active').toList();
  List<SubscriptionTrack> get _orphans =>
      (_sub?.tracks ?? []).where((t) => t.status == 'orphan' || t.status == 'removed').toList();
  List<SubscriptionTrack> get _new => _active.where((t) => t.isNew == true).toList();

  Future<void> _load() async {
    final session = context.read<SessionStore>();
    final id = widget.subscriptionId;
    try {
      _sub = await session.api.getJson('/api/subscriptions/$id', Subscription.fromJson);
    } catch (_) {}
    try {
      _stats = await session.api.getJson('/api/subscriptions/$id/stats', SubscriptionStats.fromJson);
    } catch (_) {}
    try {
      _changes = await session.api.getList('/api/subscriptions/$id/changes', PlaylistChange.fromJson);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _patch(Map<String, dynamic> changes) async {
    final sub = _sub;
    if (sub == null) return;
    setState(() => _busy = true);
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      _sub = await session.api.putJson('/api/subscriptions/${sub.id}', Subscription.fromJson, json: changes);
    } catch (e) {
      ui.notify('$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _sync() async {
    final sub = _sub;
    if (sub == null) return;
    setState(() => _busy = true);
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      final res = await session.api.postJson('/api/subscriptions/${sub.id}/sync', _SyncResult.fromJson);
      ui.notify(res.ok ? '同步完成 · +${res.added ?? 0} -${res.removed ?? 0}' : (res.error ?? '同步失败'));
      await _load();
    } catch (e) {
      ui.notify('$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _run(String task) async {
    final sub = _sub;
    if (sub == null) return;
    setState(() => _busy = true);
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      await session.api.post('/api/subscriptions/${sub.id}/run', json: {'task': task});
      ui.notify(task == 'refresh' ? '刷新已触发' : '入库已触发');
      await _load();
    } catch (e) {
      ui.notify('$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove() async {
    final sub = _sub;
    if (sub == null) return;
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      await session.api.delete('/api/subscriptions/${sub.id}');
      ui.notify('已取消订阅');
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      ui.notify('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = _sub;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(sub?.title ?? '订阅详情',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(onPressed: sub == null ? null : _sync, icon: Icon(Icons.refresh, color: MX.fg)),
        ],
      ),
      body: sub == null
          ? Center(child: CircularProgressIndicator(color: MX.ember))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _header(sub),
                const SizedBox(height: 16),
                _statsRow(),
                const SizedBox(height: 16),
                _tabSelector(),
                const SizedBox(height: 16),
                if (_tab == 'tracks') ..._tracksTab() else ..._changesTab(),
                const SizedBox(height: 20),
                _settings(sub),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _confirmDelete,
                  style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(44)),
                  icon: const Icon(Icons.notifications_off, size: 18),
                  label: const Text('取消订阅'),
                ),
              ],
            ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('取消订阅', style: TextStyle(color: MX.fg)),
        content: Text('确定取消订阅「${_sub?.title ?? ''}」？', style: TextStyle(color: MX.dim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消', style: TextStyle(color: MX.dim))),
          TextButton(onPressed: () { Navigator.pop(ctx); _remove(); }, child: const Text('取消订阅', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _header(Subscription sub) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: MX.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: MX.hairline, width: 0.5)),
        child: Row(
          children: [
            CoverArt(src: sub.coverUrl, size: 72, corner: 12),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sub.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      PlatformChip(id: sub.platform),
                      const SizedBox(width: 6),
                      Text('${sub.kind == 'chart' ? '榜单' : '歌单'} · ${sub.trackCount} 首',
                          style: TextStyle(color: MX.dim, fontSize: 12)),
                    ],
                  ),
                  if (sub.lastSyncAt?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 4),
                    Text('上次同步：${_relative(sub.lastSyncAt)}', style: TextStyle(color: MX.mute, fontSize: 11)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _statsRow() => Row(
        children: [
          _statCard('新增', _stats?.addedLastSync ?? 0, Colors.green, Icons.add),
          const SizedBox(width: 12),
          _statCard('移除', _stats?.removedLastSync ?? 0, Colors.red, Icons.remove),
          const SizedBox(width: 12),
          _statCard('本地可用', _orphans.length, Colors.orange, Icons.storage),
        ],
      );

  Widget _statCard(String title, int value, Color color, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 6),
              Text('$value', style: TextStyle(color: MX.fg, fontSize: 18, fontWeight: FontWeight.w600)),
              Text(title, style: TextStyle(color: MX.dim, fontSize: 11)),
            ],
          ),
        ),
      );

  Widget _tabSelector() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: MX.hairline, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _tabBtn('tracks', '曲目'),
            _tabBtn('changes', '变更记录'),
          ],
        ),
      );

  Widget _tabBtn(String id, String label) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: _tab == id ? MX.ember.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(color: _tab == id ? MX.ember : MX.dim, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ),
      );

  List<Widget> _tracksTab() {
    if (_active.isEmpty) {
      return [_infoBox(Icons.music_note, '暂无曲目')];
    }
    return [
      if (_new.isNotEmpty) _trackSection('新增 ${_new.length} 首', _new, true),
      if (_new.isNotEmpty) const SizedBox(height: 16),
      _trackSection('全部 ${_active.length} 首', _active, false),
      if (_orphans.isNotEmpty) ...[
        const SizedBox(height: 16),
        _orphanSection(),
      ],
    ];
  }

  Widget _trackSection(String title, List<SubscriptionTrack> tracks, bool highlight) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: highlight ? Colors.green : MX.dim, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: MX.hairline, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (var i = 0; i < tracks.length; i++) ...[
                  _trackRow(tracks[i], dimmed: false),
                  if (i < tracks.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      );

  Widget _orphanSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showOrphans = !_showOrphans),
            child: Row(
              children: [
                Icon(Icons.storage, size: 16, color: Colors.orange),
                const SizedBox(width: 6),
                Text('已移除（本地可用）${_orphans.length} 首',
                    style: const TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.w500)),
                const Spacer(),
                Icon(_showOrphans ? Icons.expand_more : Icons.chevron_right, size: 18, color: MX.dim),
              ],
            ),
          ),
          if (_showOrphans) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: MX.hairline, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  for (var i = 0; i < _orphans.length; i++) ...[
                    _trackRow(_orphans[i], dimmed: true),
                    if (i < _orphans.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        ],
      );

  Widget _trackRow(SubscriptionTrack track, {required bool dimmed}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Opacity(
          opacity: dimmed ? 0.7 : 1,
          child: Row(
            children: [
              CoverArt(src: track.artworkUrl, size: 40, corner: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(track.title.isEmpty ? '未知曲目' : track.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: dimmed ? MX.dim : MX.fg, fontSize: 14)),
                        ),
                        if (track.isNew == true) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                            child: const Text('NEW', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    if (track.artistText.isNotEmpty)
                      Text(track.artistText, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MX.mute, fontSize: 12)),
                  ],
                ),
              ),
              if (dimmed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: const Text('已移除', style: TextStyle(color: Colors.orange, fontSize: 9)),
                )
              else if (track.hasLocalFile == true)
                Icon(Icons.download_done, size: 15, color: Colors.green),
            ],
          ),
        ),
      );

  List<Widget> _changesTab() {
    if (_changes.isEmpty) return [_infoBox(Icons.schedule, '暂无变更记录')];
    return [
      Container(
        decoration: BoxDecoration(color: MX.hairline, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            for (var i = 0; i < _changes.length; i++) ...[
              _changeRow(_changes[i]),
              if (i < _changes.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _changeRow(PlaylistChange change) {
    IconData icon;
    Color color;
    switch (change.type) {
      case 'ADDED':
        icon = Icons.add_circle;
        color = Colors.green;
        break;
      case 'REMOVED':
        icon = Icons.remove_circle;
        color = Colors.red;
        break;
      case 'REORDERED':
        icon = Icons.swap_vert_circle;
        color = Colors.blue;
        break;
      default:
        icon = Icons.info;
        color = Colors.orange;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(change.trackTitle ?? '未知曲目', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: MX.fg, fontSize: 14)),
                if (change.trackArtist?.isNotEmpty ?? false)
                  Text(change.trackArtist!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MX.mute, fontSize: 12)),
              ],
            ),
          ),
          Text(_relative(change.createdAt), style: TextStyle(color: MX.mute, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _settings(Subscription sub) => Column(
        children: [
          _cronSetting('定时刷新', Icons.refresh, sub.refreshEnabled, sub.refreshCron, '0 */6 * * *',
              (v) => _patch({'refreshEnabled': v}), (cron) => _patch({'refreshCron': cron}),
              sub.lastRefreshStatus, sub.lastRefreshAt, sub.lastRefreshError),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('按最高可用完整音质入库；失败可在入库记录中重试。', style: TextStyle(color: MX.dim, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          _cronSetting('定时入库', Icons.download, sub.ingestEnabled, sub.ingestCron, '30 3 * * *',
              (v) => _patch({'ingestEnabled': v}), (cron) => _patch({'ingestCron': cron}),
              sub.lastIngestStatus, sub.lastIngestAt, sub.lastIngestError),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run('refresh'),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('立即刷新'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run('ingest'),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('立即入库'),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _cronSetting(String title, IconData icon, bool enabled, String cron, String hint,
      ValueChanged<bool> onToggle, ValueChanged<String> onCron,
      String? status, String? at, String? error) {
    final ctl = TextEditingController(text: cron);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: MX.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: MX.hairline, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: MX.ember),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: MX.fg, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Switch(value: enabled, activeColor: MX.ember, onChanged: _busy ? null : onToggle),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Cron', style: TextStyle(color: MX.fg)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: ctl,
                    enabled: !_busy,
                    textAlign: TextAlign.right,
                    onSubmitted: (v) => onCron(v.trim()),
                    style: TextStyle(color: MX.fg, fontFamily: 'monospace', fontSize: 14),
                    decoration: InputDecoration(
                        hintText: hint, hintStyle: TextStyle(color: MX.mute), isDense: true, border: InputBorder.none),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(
                    color: !enabled ? Colors.grey.withOpacity(0.4)
                        : status == 'ok' ? Colors.green.withOpacity(0.85)
                        : status == 'error' ? Colors.red.withOpacity(0.85)
                        : MX.ember.withOpacity(0.7),
                    shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_statusText(enabled, status, at, error),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MX.dim, fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _statusText(bool enabled, String? status, String? at, String? error) {
    if (!enabled) return '已关闭';
    final parts = <String>[];
    if (error?.isNotEmpty ?? false) {
      parts.add(error!);
    } else {
      switch (status) {
        case 'ok':
          parts.add('最近一次正常');
          break;
        case 'error':
          parts.add('最近一次失败');
          break;
        case null:
          parts.add('尚未运行');
          break;
        default:
          parts.add(status);
      }
    }
    if (at?.isNotEmpty ?? false) parts.add(_relative(at));
    return parts.join(' · ');
  }

  Widget _infoBox(IconData icon, String text) => Container(
        height: 80,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: MX.dim, size: 30),
            const SizedBox(height: 6),
            Text(text, style: TextStyle(color: MX.dim, fontSize: 13)),
          ],
        ),
      );
}
