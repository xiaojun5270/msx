import 'json.dart';
import 'track.dart';

/// UI-safe playback source lifecycle — mirrors Swift `PlaybackSourcePhase`.
enum PlaybackSourcePhase {
  idle,
  resolving,
  preparing,
  connecting,
  buffering,
  ready,
  playing,
  failed,
}

class PlaybackSourceProgress {
  final PlaybackSourcePhase phase;
  final String? detail;

  PlaybackSourceProgress({required this.phase, String? detail})
      : detail = _nilIfEmpty(detail);

  static String? _nilIfEmpty(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  String get title {
    switch (phase) {
      case PlaybackSourcePhase.idle:
        return '等待播放';
      case PlaybackSourcePhase.resolving:
        return '正在解析音源';
      case PlaybackSourcePhase.preparing:
        return '正在准备音源';
      case PlaybackSourcePhase.connecting:
        return '正在连接音源';
      case PlaybackSourcePhase.buffering:
        return '正在缓冲音频';
      case PlaybackSourcePhase.ready:
        return '音源已就绪';
      case PlaybackSourcePhase.playing:
        return '正在播放';
      case PlaybackSourcePhase.failed:
        return '音源不可用';
    }
  }

  String get displayText => detail == null ? title : '$title：$detail';

  bool get isWorking {
    switch (phase) {
      case PlaybackSourcePhase.resolving:
      case PlaybackSourcePhase.preparing:
      case PlaybackSourcePhase.connecting:
      case PlaybackSourcePhase.buffering:
        return true;
      default:
        return false;
    }
  }

  bool get isError => phase == PlaybackSourcePhase.failed;
  bool get isVisible => phase != PlaybackSourcePhase.idle;

  static String? preparationDetail({required String status, String? reason}) {
    switch (status) {
      case 'preparing':
        return '正在准备可播放音源';
      case 'pending':
        return '音源排队中';
      case 'retry_wait':
        return '正在重试音源';
      default:
        final t = reason?.trim();
        return (t == null || t.isEmpty) ? null : t;
    }
  }
}

/// Mirrors Swift `PlaybackSessionResponse`.
class PlaybackSessionResponse {
  final String status;
  final String? playIntentId;
  final String? sessionId;
  final String? streamUrl;
  final String? recordingCorrespondence;
  final String? sourceKind;
  final String? sourcePlatform;
  final String? sourceTrackId;
  final String? fileId;
  final String? reason;
  final String? autoWaitUntil;
  final String? playbackKind;

  const PlaybackSessionResponse({
    this.status = '',
    this.playIntentId,
    this.sessionId,
    this.streamUrl,
    this.recordingCorrespondence,
    this.sourceKind,
    this.sourcePlatform,
    this.sourceTrackId,
    this.fileId,
    this.reason,
    this.autoWaitUntil,
    this.playbackKind,
  });

  bool get isWaiting => ['preparing', 'pending', 'retry_wait'].contains(status);
  bool get isPreview => ['origin_preview', 'explicit_preview'].contains(reason);
  bool get hasTransport => playbackKind != null;

  factory PlaybackSessionResponse.fromJson(Map<String, dynamic> c) {
    final playback = asMap(c['playback']);
    return PlaybackSessionResponse(
      status: asStringOr(c['status'], ''),
      playIntentId: asString(c['playIntentId']),
      sessionId: asString(c['sessionId']),
      streamUrl: asString(c['streamUrl']),
      recordingCorrespondence: asString(c['recordingCorrespondence']),
      sourceKind: asString(c['sourceKind']),
      sourcePlatform: asString(c['sourcePlatform']),
      sourceTrackId: flexIdOrNull(c['sourceTrackId']),
      fileId: flexIdOrNull(c['fileId']),
      reason: asString(c['reason']),
      autoWaitUntil: asString(c['autoWaitUntil']),
      playbackKind: playback != null ? asString(playback['kind']) : null,
    );
  }
}

class SubstitutionOutcome {
  final String status;
  final String? reason;
  final SubstitutionDecision? decision;
  const SubstitutionOutcome({this.status = '', this.reason, this.decision});

  bool get canRebuildSession => status == 'active' || status == 'ready';
  String get message {
    switch (status) {
      case 'active':
      case 'ready':
        return '音源已验证并保存';
      case 'pending':
        return '音源仍在验证，请稍后重试';
      default:
        return reason ?? '音源验证失败，请重试';
    }
  }

  factory SubstitutionOutcome.fromJson(Map<String, dynamic> c) => SubstitutionOutcome(
        status: asStringOr(c['status'], ''),
        reason: asString(c['reason']),
        decision: asMap(c['decision']) != null
            ? SubstitutionDecision.fromJson(asMap(c['decision'])!)
            : null,
      );
}

class SubstitutionDecision {
  final String? sourceKind;
  final String? sourcePlatform;
  final String? sourceTrackId;
  const SubstitutionDecision({this.sourceKind, this.sourcePlatform, this.sourceTrackId});
  factory SubstitutionDecision.fromJson(Map<String, dynamic> c) => SubstitutionDecision(
        sourceKind: asString(c['sourceKind']),
        sourcePlatform: asString(c['sourcePlatform']),
        sourceTrackId: flexIdOrNull(c['sourceTrackId']),
      );
}

class SourceSubstitutionRun {
  final String id;
  final String status;
  final int? total;
  final int? completed;
  final int? failed;
  final bool? backgroundIngest;
  final SourceRunIngestion? ingestion;
  final List<SourceRunItem>? items;
  final int? version;
  final List<SourceRunAction>? availableActions;

  const SourceSubstitutionRun({
    required this.id,
    this.status = '',
    this.total,
    this.completed,
    this.failed,
    this.backgroundIngest,
    this.ingestion,
    this.items,
    this.version,
    this.availableActions,
  });

  bool get canRetry =>
      availableActions?.any((a) => a.action == 'retry' && a.enabled) ?? false;

  bool get isFinished => [
        'completed',
        'failed',
        'cancelled',
        'partial',
        'completed_with_errors',
      ].contains(status);

  factory SourceSubstitutionRun.fromJson(Map<String, dynamic> c) => SourceSubstitutionRun(
        id: c['id'] != null ? flexId(c['id']) : '',
        status: asStringOr(c['status'], ''),
        total: asInt(c['total']),
        completed: asInt(c['completed']),
        failed: asInt(c['failed']),
        backgroundIngest: asBool(c['backgroundIngest']),
        ingestion: asMap(c['ingestion']) != null
            ? SourceRunIngestion.fromJson(asMap(c['ingestion'])!)
            : null,
        items: c['items'] is List ? decodeList(c['items'], SourceRunItem.fromJson) : null,
        version: asInt(c['version']),
        availableActions: c['availableActions'] is List
            ? decodeList(c['availableActions'], SourceRunAction.fromJson)
            : null,
      );
}

class SourceRunItem {
  final String id;
  final String? title;
  final String status;
  final String? error;
  const SourceRunItem({required this.id, this.title, this.status = '', this.error});
  factory SourceRunItem.fromJson(Map<String, dynamic> c) => SourceRunItem(
        id: c['id'] != null ? flexId(c['id']) : '',
        title: asString(c['title']),
        status: asStringOr(c['status'], ''),
        error: asString(c['error']),
      );
}

class SourceRunAction {
  final String action;
  final bool enabled;
  const SourceRunAction({this.action = '', this.enabled = false});
  factory SourceRunAction.fromJson(Map<String, dynamic> c) => SourceRunAction(
        action: asStringOr(c['action'], ''),
        enabled: asBool(c['enabled']) ?? false,
      );
}

class SourceRunIngestion {
  final int queued;
  final int running;
  final int completed;
  final int failed;
  const SourceRunIngestion({this.queued = 0, this.running = 0, this.completed = 0, this.failed = 0});
  factory SourceRunIngestion.fromJson(Map<String, dynamic> c) => SourceRunIngestion(
        queued: asInt(c['queued']) ?? 0,
        running: asInt(c['running']) ?? 0,
        completed: asInt(c['completed']) ?? 0,
        failed: asInt(c['failed']) ?? 0,
      );
}

class SourceRunsResponse {
  final List<SourceSubstitutionRun> items;
  final String? nextCursor;
  const SourceRunsResponse({this.items = const [], this.nextCursor});
  factory SourceRunsResponse.fromJson(Map<String, dynamic> c) => SourceRunsResponse(
        items: decodeList(c['items'], SourceSubstitutionRun.fromJson),
        nextCursor: asString(c['nextCursor']),
      );
}

class SourceRunActionResponse {
  final bool ok;
  final String? reason;
  const SourceRunActionResponse({this.ok = false, this.reason});
  factory SourceRunActionResponse.fromJson(Map<String, dynamic> c) =>
      SourceRunActionResponse(ok: asBool(c['ok']) ?? false, reason: asString(c['reason']));
}

class SourceOverrideContext {
  final int version;
  final List<Track> candidates;
  const SourceOverrideContext({this.version = 0, this.candidates = const []});
  factory SourceOverrideContext.fromJson(Map<String, dynamic> c) => SourceOverrideContext(
        version: asInt(c['version']) ?? 0,
        candidates: decodeList(c['candidates'], Track.fromJson),
      );
}

class PlaybackTelemetryReceipt {
  final bool accepted;
  const PlaybackTelemetryReceipt({this.accepted = false});
  factory PlaybackTelemetryReceipt.fromJson(Map<String, dynamic> c) =>
      PlaybackTelemetryReceipt(accepted: asBool(c['accepted']) ?? false);
}

class PlaybackPreheatReceipt {
  final int accepted;
  final String? reason;
  final int? created;
  final int? retained;
  final int? retired;
  final int? warmed;
  const PlaybackPreheatReceipt({
    this.accepted = 0,
    this.reason,
    this.created,
    this.retained,
    this.retired,
    this.warmed,
  });
  factory PlaybackPreheatReceipt.fromJson(Map<String, dynamic> c) => PlaybackPreheatReceipt(
        accepted: asInt(c['accepted']) ?? 0,
        reason: asString(c['reason']),
        created: asInt(c['created']),
        retained: asInt(c['retained']),
        retired: asInt(c['retired']),
        warmed: asInt(c['warmed']),
      );
}

enum SourceSwitchResult { notRequested, switched, pending, failed, cancelled }

class SourceApplyReceipt {
  final SubstitutionOutcome outcome;
  final SourceSwitchResult switchResult;
  const SourceApplyReceipt({required this.outcome, required this.switchResult});
  bool get saved => outcome.canRebuildSession;
  String get message {
    if (!saved) return outcome.message;
    switch (switchResult) {
      case SourceSwitchResult.notRequested:
        return '来源已保存，原曲信息不变';
      case SourceSwitchResult.switched:
        return '来源已保存，当前播放已切换';
      case SourceSwitchResult.pending:
        return '来源已保存，当前音源仍在准备';
      case SourceSwitchResult.failed:
        return '来源已保存，但当前播放切换失败，可重试播放';
      case SourceSwitchResult.cancelled:
        return '来源已保存，播放状态已变化，未继续切换';
    }
  }
}

// Policies --------------------------------------------------------------------

class SourceSessionPolicy {
  static bool isCurrent({
    required String expectedKey,
    required int expectedGeneration,
    String? key,
    required int generation,
  }) =>
      expectedKey == key && expectedGeneration == generation;

  static String pathComponent(String value) => Uri.encodeComponent(value);
}

/// Wire payloads — mirrors Swift `SourceRequestPayload`.
class SourceRequestPayload {
  static Map<String, dynamic> playback(Track track, String intentId, {bool recover = false}) {
    final body = <String, dynamic>{
      'playIntentId': intentId,
      'platform': track.platform,
      'trackId': track.id,
      'payload': track.identityPayload(),
      'supportedTransports': ['http'],
    };
    if (recover) body['recover'] = true;
    if (track.historyReplay) body['historyReplay'] = true;
    return body;
  }

  static Map<String, dynamic> apply(Track original, Track candidate, {int? version}) {
    final choice = <String, dynamic>{'platform': candidate.platform, 'id': candidate.id};
    if (candidate.quality != null) choice['quality'] = candidate.quality;
    final body = <String, dynamic>{'candidate': choice, 'payload': original.identityPayload()};
    if (version != null) body['version'] = version;
    return body;
  }

  static Map<String, dynamic> organize(List<Track> tracks, {bool backgroundIngest = false, required String requestId}) {
    return {
      'scope': 'tracks',
      'platform': tracks.isNotEmpty ? tracks.first.platform : '',
      'tracks': tracks.map((t) => t.identityPayload()).toList(),
      'operation': 'organize',
      'backgroundIngest': backgroundIngest,
      'idempotencyKey': requestId,
    };
  }
}

class PlaybackPreheatPolicy {
  static const candidateLimit = 5;
  static const baselineWarmWindow = 3;

  static List<int> upcoming({required List<int> order, required int current, required int repeatMode}) {
    final position = order.indexOf(current);
    if (position < 0 || order.isEmpty) return [];
    if (repeatMode == 1) return [current];
    final result = <int>[];
    var cursor = position + 1;
    while (result.length < candidateLimit) {
      if (cursor == order.length) {
        if (repeatMode != 2) break;
        cursor = 0;
      }
      final candidate = order[cursor];
      if (candidate == current) break;
      result.add(candidate);
      cursor += 1;
    }
    return result;
  }

  static List<Track> warmWindow(List<Track> candidates, {required int limit}) {
    final n = limit < 0 ? 0 : (limit < candidateLimit ? limit : candidateLimit);
    return candidates.take(n).toList();
  }
}

class PlaybackSessionReusePolicy {
  static const capacity = 3;
  static const lifetime = Duration(minutes: 2);

  static bool isFresh(DateTime createdAt, [DateTime? now]) {
    final elapsed = (now ?? DateTime.now()).difference(createdAt);
    return elapsed >= Duration.zero && elapsed < lifetime;
  }

  static double playbackPosition({required double requested, required double duration}) {
    if (!requested.isFinite || requested < 0) return 0;
    if (!duration.isFinite || duration <= 0) return requested;
    return requested < duration ? requested : duration;
  }
}

class SourceEndPolicy {
  static bool isNaturalEnd({
    required double position,
    required double itemDuration,
    required double trackDuration,
    required bool loading,
    required bool trial,
  }) {
    if (loading) return false;
    final t = position.isFinite ? position : 0;
    if (t < 1) return false;
    if (trial) {
      final d = itemDuration.isFinite && itemDuration > 1 ? itemDuration : trackDuration;
      return d > 1 && t >= d - 1.5;
    }
    final expected = trackDuration.isFinite && trackDuration > 1 ? trackDuration : itemDuration;
    return expected > 1 && t >= expected - 1.5;
  }
}

class SourceHandoffPolicy {
  static double position({
    required double current,
    String? previousSource,
    String? nextSource,
    String? previousCorrespondence,
    String? nextCorrespondence,
  }) {
    if (previousSource == null || nextSource == null) return 0;
    final same = previousSource == nextSource ||
        (previousCorrespondence == 'same_recording' && nextCorrespondence == 'same_recording');
    if (!same || !current.isFinite || current <= 0) return 0;
    return current;
  }
}

/// Mirrors Swift `SourcePick`.
class SourcePick {
  static int playable(Track t) {
    if (t.streamUrl != null || t.playable == true) return 3;
    if (t.vip == true) return 2;
    return 0;
  }

  static int quality(Track t) {
    final q = (t.quality ?? t.format ?? '').toLowerCase();
    if (q.contains('flac') || q.contains('lossless') || q.contains('无损')) return 5;
    final b = t.bitrate;
    if (b != null) {
      if (b >= 320000) return 4;
      if (b >= 192000) return 3;
      if (b >= 128000) return 2;
      return 1;
    }
    return 0;
  }

  static String kind(Track t) {
    if (t.streamUrl != null || t.playable == true) return 'stream';
    if (t.vip == true) return 'vip';
    return 'jump';
  }

  static String qualityLabel(Track t) {
    if ((t.quality ?? '').isNotEmpty) return t.quality!;
    if ((t.format ?? '').isNotEmpty) return t.format!.toUpperCase();
    final b = t.bitrate;
    if (b != null && b > 0) return '${(b / 1000).round()} kbps';
    if (kind(t) == 'jump') return '仅跳转';
    return '可播放';
  }

  static String status(Track t, {required bool bound}) {
    switch (kind(t)) {
      case 'local':
        return '本地';
      case 'jump':
        return '仅跳转';
      case 'vip':
        return bound ? '已登录' : 'VIP';
      default:
        return bound ? '已登录' : '可播放';
    }
  }

  static List<T> mix<T>(List<T> items, {required int n, required String Function(T) platform}) {
    final buckets = <String, List<T>>{};
    for (final item in items) {
      buckets.putIfAbsent(platform(item), () => []).add(item);
    }
    final keys = buckets.keys.toList()..sort();
    final cursor = <String, int>{};
    final out = <T>[];
    while (out.length < n) {
      var added = false;
      for (final key in keys) {
        final i = cursor[key] ?? 0;
        final bucket = buckets[key] ?? const [];
        if (i >= bucket.length) continue;
        out.add(bucket[i]);
        cursor[key] = i + 1;
        added = true;
        if (out.length >= n) break;
      }
      if (!added) break;
    }
    return out;
  }
}
