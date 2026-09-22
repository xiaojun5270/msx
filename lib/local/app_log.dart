import 'package:flutter/foundation.dart';

/// Client-side log levels, mirroring Swift `AppLogLevel`.
enum AppLogLevel {
  debug,
  info,
  warn,
  error;

  static AppLogLevel? fromRaw(String raw) {
    for (final l in AppLogLevel.values) {
      if (l.name == raw) return l;
    }
    return null;
  }

  int get rank => index;
}

/// Client-side log categories, mirroring Swift `AppLogCategory`.
enum AppLogCategory {
  app,
  network,
  player,
  auth,
  library,
  ui;

  String get title {
    switch (this) {
      case AppLogCategory.app:
        return '应用';
      case AppLogCategory.network:
        return '网络';
      case AppLogCategory.player:
        return '播放';
      case AppLogCategory.auth:
        return '账号';
      case AppLogCategory.library:
        return '音乐库';
      case AppLogCategory.ui:
        return '界面';
    }
  }

  static AppLogCategory? fromRaw(String raw) {
    for (final c in AppLogCategory.values) {
      if (c.name == raw) return c;
    }
    return null;
  }
}

@immutable
class AppLogRecord {
  final String id;
  final DateTime ts;
  final AppLogLevel level;
  final AppLogCategory category;
  final String message;
  final Map<String, String> fields;

  const AppLogRecord({
    required this.id,
    required this.ts,
    required this.level,
    required this.category,
    required this.message,
    this.fields = const {},
  });

  String get fieldsLine => (fields.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)))
      .map((e) => '${e.key}=${e.value}')
      .join(' ');
}

/// In-memory ring buffer of client log records. Mirrors Swift `LocalLogStore`.
/// Persistence is intentionally omitted — the Swift store is also volatile
/// beyond the current process for the mobile client.
class LocalLogStore extends ChangeNotifier {
  LocalLogStore._();
  static final LocalLogStore shared = LocalLogStore._();

  static const _capacity = 1000;
  final List<AppLogRecord> _records = [];
  int _seq = 0;

  void log(AppLogLevel level, AppLogCategory category, String message,
      {Map<String, String> fields = const {}}) {
    _records.add(AppLogRecord(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      ts: DateTime.now(),
      level: level,
      category: category,
      message: message,
      fields: fields,
    ));
    if (_records.length > _capacity) {
      _records.removeRange(0, _records.length - _capacity);
    }
    notifyListeners();
  }

  void debug(AppLogCategory c, String m, {Map<String, String> f = const {}}) => log(AppLogLevel.debug, c, m, fields: f);
  void info(AppLogCategory c, String m, {Map<String, String> f = const {}}) => log(AppLogLevel.info, c, m, fields: f);
  void warn(AppLogCategory c, String m, {Map<String, String> f = const {}}) => log(AppLogLevel.warn, c, m, fields: f);
  void error(AppLogCategory c, String m, {Map<String, String> f = const {}}) => log(AppLogLevel.error, c, m, fields: f);

  List<AppLogRecord> recent({
    AppLogLevel? level,
    AppLogCategory? category,
    String search = '',
    int limit = 400,
  }) {
    final q = search.trim().toLowerCase();
    final filtered = _records.where((r) {
      if (level != null && r.level != level) return false;
      if (category != null && r.category != category) return false;
      if (q.isNotEmpty) {
        final hay = '${r.message} ${r.fieldsLine}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    // Newest first.
    filtered.sort((a, b) => b.ts.compareTo(a.ts));
    return filtered.take(limit).toList();
  }

  String exportText() {
    final buf = StringBuffer();
    for (final r in _records) {
      buf.writeln('${r.ts.toIso8601String()} [${r.level.name.toUpperCase()}] '
          '${r.category.name} ${r.message}'
          '${r.fields.isEmpty ? '' : ' | ${r.fieldsLine}'}');
    }
    return buf.toString();
  }

  void clear() {
    _records.clear();
    notifyListeners();
  }
}
