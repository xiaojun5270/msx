import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../local/app_log.dart';
import '../models/models.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/theme.dart';

String _enc(String s) => Uri.encodeComponent(s);

String _fmtTime(String ts) {
  final date = DateTime.tryParse(ts);
  if (date == null) return ts;
  final l = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}/${two(l.month)}/${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

Color _levelColor(String level) {
  switch (level) {
    case 'error':
      return Colors.red.withOpacity(0.8);
    case 'warn':
      return Colors.orange.withOpacity(0.8);
    case 'debug':
      return Colors.cyan.withOpacity(0.7);
    default:
      return Colors.green.withOpacity(0.7);
  }
}

IconData _levelIcon(String level) {
  switch (level) {
    case 'error':
      return Icons.dangerous;
    case 'warn':
      return Icons.warning;
    case 'debug':
      return Icons.bug_report;
    default:
      return Icons.info;
  }
}

const _levelOptions = [
  ('all', '全部级别'),
  ('debug', '调试'),
  ('info', '信息'),
  ('warn', '警告'),
  ('error', '错误'),
];

// ---------------------------------------------------------------------------
// ServerLogsView
// ---------------------------------------------------------------------------

class ServerLogsView extends StatefulWidget {
  const ServerLogsView({super.key});
  @override
  State<ServerLogsView> createState() => _ServerLogsViewState();
}

class _ServerLogsViewState extends State<ServerLogsView> {
  static const _scopes = ['library', 'schedule', 'subscription', 'health', 'auth'];
  static const _limit = 100;

  List<ServerLog> _logs = [];
  int _total = 0;
  bool _loading = true;
  String _level = 'all';
  String _scope = 'all';
  String _search = '';
  Timer? _searchDebounce;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startWatch());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  String get _queryPath {
    final parts = <String>[];
    if (_level != 'all') parts.add('level=$_level');
    if (_scope != 'all') parts.add('scope=$_scope');
    if (_search.isNotEmpty) parts.add('search=${_enc(_search)}');
    parts.add('limit=$_limit');
    return '/api/logs?${parts.join('&')}';
  }

  void _startWatch() {
    _refresh();
    _scheduleNext();
  }

  void _scheduleNext() {
    _poll?.cancel();
    final hasErrors = _logs.any((l) => l.level == 'error');
    _poll = Timer(Duration(milliseconds: hasErrors ? 800 : 2400), () async {
      if (!mounted) return;
      await _refresh();
      _scheduleNext();
    });
  }

  Future<void> _refresh() async {
    final session = context.read<SessionStore>();
    try {
      final box = await session.api.getJson(_queryPath, ServerLogsBox.fromJson);
      _logs = box.items ?? [];
      _total = box.total ?? 0;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    final session = context.read<SessionStore>();
    final path = '$_queryPath&offset=${_logs.length}';
    try {
      final box = await session.api.getJson(path, ServerLogsBox.fromJson);
      if (box.items != null) setState(() => _logs = [..._logs, ...box.items!]);
    } catch (_) {}
  }

  void _onSearch(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _search = v.trim();
      _refresh();
    });
  }

  Future<void> _clear() async {
    final session = context.read<SessionStore>();
    final ui = context.read<UIStore>();
    try {
      await session.api.delete('/api/logs');
      ui.notify('已清空日志');
      await _refresh();
    } catch (e) {
      ui.notify('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.read<SessionStore>().role == 'admin';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text('服务日志', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
        actions: [
          _filterMenu(),
          if (isAdmin)
            IconButton(
              onPressed: _clear,
              icon: Icon(Icons.delete_outline, color: MX.fg),
              tooltip: '清空日志',
            ),
        ],
      ),
      body: RefreshIndicator(
        color: MX.ember,
        onRefresh: _refresh,
        child: Column(
          children: [
            _searchBar(_onSearch),
            Expanded(
              child: _loading && _logs.isEmpty
                  ? Center(child: CircularProgressIndicator(color: MX.ember))
                  : _logs.isEmpty
                      ? _empty('暂无日志记录')
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                          itemCount: _logs.length + 2,
                          itemBuilder: (_, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                                child: Text('共 $_total 条', style: TextStyle(color: MX.dim, fontSize: 13)),
                              );
                            }
                            if (i == _logs.length + 1) {
                              if (_logs.length >= _total) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Center(child: TextButton(onPressed: _loadMore, child: Text('加载更多', style: TextStyle(color: MX.ember)))),
                              );
                            }
                            return _ServerLogRow(log: _logs[i - 1]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterMenu() => PopupMenuButton<String>(
        icon: Icon(Icons.filter_alt_outlined, color: MX.ember),
        color: MX.panel,
        onSelected: (v) {
          setState(() {
            if (v.startsWith('l:')) _level = v.substring(2);
            if (v.startsWith('s:')) _scope = v.substring(2);
          });
          _refresh();
        },
        itemBuilder: (_) => [
          PopupMenuItem(enabled: false, child: Text('级别', style: TextStyle(color: MX.dim, fontSize: 12))),
          for (final o in _levelOptions) PopupMenuItem(value: 'l:${o.$1}', child: _check(o.$2, _level == o.$1)),
          const PopupMenuDivider(),
          PopupMenuItem(enabled: false, child: Text('范围', style: TextStyle(color: MX.dim, fontSize: 12))),
          PopupMenuItem(value: 's:all', child: _check('全部范围', _scope == 'all')),
          for (final s in _scopes) PopupMenuItem(value: 's:$s', child: _check(s, _scope == s)),
        ],
      );

  Widget _check(String text, bool on) => Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(color: MX.fg))),
          if (on) Icon(Icons.check, size: 16, color: MX.ember),
        ],
      );

  Widget _empty(String text) => ListView(
        children: [
          const SizedBox(height: 90),
          Icon(Icons.manage_search, color: MX.dim, size: 46),
          const SizedBox(height: 12),
          Center(child: Text(text, style: TextStyle(color: MX.dim, fontSize: 15))),
        ],
      );
}

class _ServerLogRow extends StatefulWidget {
  final ServerLog log;
  const _ServerLogRow({required this.log});
  @override
  State<_ServerLogRow> createState() => _ServerLogRowState();
}

class _ServerLogRowState extends State<_ServerLogRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final color = _levelColor(log.level);
    final meta = log.metaPretty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: Icon(_levelIcon(log.level), size: 14, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                          child: Text(log.scope, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        Text(_fmtTime(log.createdAt), style: TextStyle(color: MX.mute, fontSize: 12)),
                        const Spacer(),
                        if (meta.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _expanded = !_expanded),
                            child: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: MX.ember),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(log.message,
                        maxLines: _expanded ? null : 3,
                        overflow: _expanded ? null : TextOverflow.ellipsis,
                        style: TextStyle(color: MX.fg, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          if (_expanded && meta.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(color: MX.hairline, borderRadius: BorderRadius.circular(10)),
              child: SingleChildScrollView(
                child: SelectableText(meta, style: TextStyle(color: MX.dim, fontSize: 12, fontFamily: 'monospace')),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ClientLogsView
// ---------------------------------------------------------------------------

class ClientLogsView extends StatefulWidget {
  const ClientLogsView({super.key});
  @override
  State<ClientLogsView> createState() => _ClientLogsViewState();
}

class _ClientLogsViewState extends State<ClientLogsView> {
  String _level = 'all';
  String _category = 'all';
  String _search = '';
  Timer? _searchDebounce;

  List<AppLogRecord> get _logs => LocalLogStore.shared.recent(
        level: _level == 'all' ? null : AppLogLevel.fromRaw(_level),
        category: _category == 'all' ? null : AppLogCategory.fromRaw(_category),
        search: _search,
      );

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearch(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () => setState(() => _search = v.trim()));
  }

  void _confirmClear() {
    final ui = context.read<UIStore>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MX.panel,
        title: Text('清空本地日志？', style: TextStyle(color: MX.fg)),
        content: Text('仅清除本机客户端日志，不影响服务端日志。', style: TextStyle(color: MX.dim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消', style: TextStyle(color: MX.dim))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              LocalLogStore.shared.clear();
              LocalLogStore.shared.info(AppLogCategory.app, 'log.cleared');
              ui.notify('已清空本地日志');
              setState(() {});
            },
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _copyLogs() {
    Clipboard.setData(ClipboardData(text: LocalLogStore.shared.exportText()));
    context.read<UIStore>().notify('日志已复制到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalLogStore.shared,
      builder: (context, _) {
        final logs = _logs;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: Text('客户端日志', style: TextStyle(color: MX.fg, fontWeight: FontWeight.bold)),
            actions: [
              _filterMenu(),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, color: MX.fg),
                color: MX.panel,
                onSelected: (v) {
                  if (v == 'copy') _copyLogs();
                  if (v == 'clear') _confirmClear();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'copy', child: Text('复制全部', style: TextStyle(color: MX.fg))),
                  PopupMenuItem(value: 'clear', child: const Text('清空日志', style: TextStyle(color: Colors.red))),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              _searchBar(_onSearch),
              Expanded(
                child: logs.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 90),
                        Icon(Icons.description_outlined, color: MX.dim, size: 46),
                        const SizedBox(height: 12),
                        Center(child: Text('暂无本地日志', style: TextStyle(color: MX.dim, fontSize: 15))),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                        itemCount: logs.length + 1,
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                              child: Text('共 ${logs.length} 条', style: TextStyle(color: MX.dim, fontSize: 13)),
                            );
                          }
                          return _ClientLogRow(log: logs[i - 1]);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filterMenu() => PopupMenuButton<String>(
        icon: Icon(Icons.filter_alt_outlined, color: MX.ember),
        color: MX.panel,
        onSelected: (v) {
          setState(() {
            if (v.startsWith('l:')) _level = v.substring(2);
            if (v.startsWith('c:')) _category = v.substring(2);
          });
        },
        itemBuilder: (_) => [
          PopupMenuItem(enabled: false, child: Text('级别', style: TextStyle(color: MX.dim, fontSize: 12))),
          for (final o in _levelOptions) PopupMenuItem(value: 'l:${o.$1}', child: _check(o.$2, _level == o.$1)),
          const PopupMenuDivider(),
          PopupMenuItem(enabled: false, child: Text('分类', style: TextStyle(color: MX.dim, fontSize: 12))),
          PopupMenuItem(value: 'c:all', child: _check('全部分类', _category == 'all')),
          for (final c in AppLogCategory.values) PopupMenuItem(value: 'c:${c.name}', child: _check(c.title, _category == c.name)),
        ],
      );

  Widget _check(String text, bool on) => Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(color: MX.fg))),
          if (on) Icon(Icons.check, size: 16, color: MX.ember),
        ],
      );
}

class _ClientLogRow extends StatefulWidget {
  final AppLogRecord log;
  const _ClientLogRow({required this.log});
  @override
  State<_ClientLogRow> createState() => _ClientLogRowState();
}

class _ClientLogRowState extends State<_ClientLogRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final color = _levelColor(log.level.name);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            child: Icon(_levelIcon(log.level.name), size: 14, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text(log.category.title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    Text(_fmtDateTime(log.ts), style: TextStyle(color: MX.mute, fontSize: 12)),
                    const Spacer(),
                    if (log.fields.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: MX.ember),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(log.message,
                    maxLines: _expanded ? null : 2,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500)),
                if (log.fields.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SelectableText(log.fieldsLine,
                        maxLines: _expanded ? null : 2,
                        style: TextStyle(color: MX.dim, fontSize: 12, fontFamily: 'monospace')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime date) {
    final l = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}/${two(l.month)}/${two(l.day)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }
}

// ---------------------------------------------------------------------------

Widget _searchBar(ValueChanged<String> onChanged) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        onChanged: onChanged,
        style: TextStyle(color: MX.fg),
        decoration: InputDecoration(
          hintText: '搜索日志消息',
          hintStyle: TextStyle(color: MX.mute),
          prefixIcon: Icon(Icons.search, color: MX.mute),
          filled: true,
          fillColor: MX.panel,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
