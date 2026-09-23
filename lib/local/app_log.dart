import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLogLevel {
  debug,
  info,
  warn,
  error;

  static AppLogLevel? fromRaw(String raw) {
    for (final level in AppLogLevel.values) {
      if (level.name == raw) return level;
    }
    return null;
  }

  int get rank => index;
}

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
    for (final category in AppLogCategory.values) {
      if (category.name == raw) return category;
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

  String get fieldsLine =>
      (fields.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => '${e.key}=${e.value}')
          .join(' ');

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': ts.toIso8601String(),
        'level': level.name,
        'category': category.name,
        'message': message,
        'fields': fields,
      };

  static AppLogRecord? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final timestamp = DateTime.tryParse(map['ts']?.toString() ?? '');
    final level = AppLogLevel.fromRaw(map['level']?.toString() ?? '');
    final category = AppLogCategory.fromRaw(map['category']?.toString() ?? '');
    if (timestamp == null || level == null || category == null) return null;
    final rawFields = map['fields'];
    final fields = <String, String>{};
    if (rawFields is Map) {
      for (final entry in rawFields.entries) {
        fields[entry.key.toString()] = entry.value.toString();
      }
    }
    return AppLogRecord(
      id: map['id']?.toString() ?? timestamp.microsecondsSinceEpoch.toString(),
      ts: timestamp,
      level: level,
      category: category,
      message: map['message']?.toString() ?? '',
      fields: fields,
    );
  }
}

/// Persistent ring buffer for client diagnostics.
class LocalLogStore extends ChangeNotifier {
  LocalLogStore._();
  static final LocalLogStore shared = LocalLogStore._();

  static const _capacity = 1000;
  static const _storageKey = 'clientLogs.v1';
  final List<AppLogRecord> _records = [];
  SharedPreferences? _preferences;
  Timer? _persistTimer;
  int _seq = 0;

  Future<void> init() async {
    if (_preferences != null) return;
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    final stored = preferences.getString(_storageKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        final decoded = jsonDecode(stored);
        if (decoded is List) {
          for (final raw in decoded) {
            final record = AppLogRecord.fromJson(raw);
            if (record != null) _records.add(record);
          }
        }
      } catch (_) {
        _records.clear();
      }
    }
    if (_records.length > _capacity) {
      _records.removeRange(0, _records.length - _capacity);
    }
    notifyListeners();
  }

  void log(
    AppLogLevel level,
    AppLogCategory category,
    String message, {
    Map<String, String> fields = const {},
  }) {
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
    _schedulePersist();
    notifyListeners();
  }

  void debug(AppLogCategory category, String message,
          {Map<String, String> fields = const {}}) =>
      log(AppLogLevel.debug, category, message, fields: fields);

  void info(AppLogCategory category, String message,
          {Map<String, String> fields = const {}}) =>
      log(AppLogLevel.info, category, message, fields: fields);

  void warn(AppLogCategory category, String message,
          {Map<String, String> fields = const {}}) =>
      log(AppLogLevel.warn, category, message, fields: fields);

  void error(AppLogCategory category, String message,
          {Map<String, String> fields = const {}}) =>
      log(AppLogLevel.error, category, message, fields: fields);

  List<AppLogRecord> recent({
    AppLogLevel? level,
    AppLogCategory? category,
    String search = '',
    int limit = _capacity,
  }) {
    final query = search.trim().toLowerCase();
    final filtered = _records.where((record) {
      if (level != null && record.level != level) return false;
      if (category != null && record.category != category) return false;
      if (query.isNotEmpty) {
        final haystack = '${record.message} ${record.fieldsLine}'.toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
    filtered.sort((a, b) => b.ts.compareTo(a.ts));
    return filtered.take(limit).toList();
  }

  String exportText() {
    final buffer = StringBuffer();
    for (final record in _records) {
      buffer.writeln(
        '${record.ts.toIso8601String()} [${record.level.name.toUpperCase()}] '
        '${record.category.name} ${record.message}'
        '${record.fields.isEmpty ? '' : ' | ${record.fieldsLine}'}',
      );
    }
    return buffer.toString();
  }

  void clear() {
    _records.clear();
    _persistTimer?.cancel();
    unawaited(_preferences?.remove(_storageKey));
    notifyListeners();
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 300), () {
      final preferences = _preferences;
      if (preferences == null) return;
      final encoded =
          jsonEncode(_records.map((record) => record.toJson()).toList());
      unawaited(preferences.setString(_storageKey, encoded));
    });
  }
}
