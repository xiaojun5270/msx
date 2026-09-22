import 'json.dart';
import 'library.dart';

class IngestReplacementCandidate {
  final String platform;
  final String id;
  final String title;
  final List<String> artists;
  final String? album;
  final double? durationMs;
  final String? artworkUrl;
  final String? quality;
  const IngestReplacementCandidate({
    this.platform = '',
    this.id = '',
    this.title = '',
    this.artists = const [],
    this.album,
    this.durationMs,
    this.artworkUrl,
    this.quality,
  });
  String get key => '$platform::$id';
  factory IngestReplacementCandidate.fromJson(Map<String, dynamic> c) =>
      IngestReplacementCandidate(
        platform: asStringOr(c['platform'], ''),
        id: c['id'] != null ? flexId(c['id']) : '',
        title: asStringOr(c['title'], ''),
        artists: flexStringList(c['artists']),
        album: asString(c['album']),
        durationMs: asDouble(c['durationMs']),
        artworkUrl: asString(c['artworkUrl']),
        quality: asString(c['quality']),
      );
}

class IngestReplacementSuggestion {
  final String reason;
  final String message;
  final IngestReplacementCandidate suggested;
  final List<IngestReplacementCandidate> candidates;
  const IngestReplacementSuggestion({
    this.reason = '',
    this.message = '',
    required this.suggested,
    this.candidates = const [],
  });
  factory IngestReplacementSuggestion.fromJson(Map<String, dynamic> c) =>
      IngestReplacementSuggestion(
        reason: asStringOr(c['reason'], ''),
        message: asStringOr(c['message'], ''),
        suggested: asMap(c['suggested']) != null
            ? IngestReplacementCandidate.fromJson(asMap(c['suggested'])!)
            : const IngestReplacementCandidate(),
        candidates: decodeList(c['candidates'], IngestReplacementCandidate.fromJson),
      );
}

class IngestJob {
  final String id;
  final String? platform;
  final String? sourceId;
  final String? quality;
  final String? title;
  final List<String>? artists;
  final String status;
  final double? bytesReceived;
  final double? bytesTotal;
  final double? percent;
  final String? error;
  final IngestReplacementSuggestion? replacementSuggestion;
  final String? artworkUrl;
  final LibraryFile? file;
  final String? createdAt;
  final String? updatedAt;

  const IngestJob({
    required this.id,
    this.platform,
    this.sourceId,
    this.quality,
    this.title,
    this.artists,
    this.status = '',
    this.bytesReceived,
    this.bytesTotal,
    this.percent,
    this.error,
    this.replacementSuggestion,
    this.artworkUrl,
    this.file,
    this.createdAt,
    this.updatedAt,
  });

  factory IngestJob.fromJson(Map<String, dynamic> c) => IngestJob(
        id: c['id'] != null ? flexId(c['id']) : '',
        platform: asString(c['platform']),
        sourceId: flexIdOrNull(c['sourceId']),
        quality: asString(c['quality']),
        title: asString(c['title']),
        artists: c['artists'] != null ? flexStringList(c['artists']) : null,
        status: asStringOr(c['status'], ''),
        bytesReceived: asDouble(c['bytesReceived']),
        bytesTotal: asDouble(c['bytesTotal']),
        percent: asDouble(c['percent']),
        error: asString(c['error']),
        replacementSuggestion: asMap(c['replacementSuggestion']) != null
            ? IngestReplacementSuggestion.fromJson(asMap(c['replacementSuggestion'])!)
            : null,
        artworkUrl: asString(c['artworkUrl']),
        file: asMap(c['file']) != null ? LibraryFile.fromJson(asMap(c['file'])!) : null,
        createdAt: asString(c['createdAt']),
        updatedAt: asString(c['updatedAt']),
      );
}

class IngestJobsBox {
  final List<IngestJob>? items;
  final int? total;
  const IngestJobsBox({this.items, this.total});
  factory IngestJobsBox.fromJson(Map<String, dynamic> c) => IngestJobsBox(
        items: c['items'] is List ? decodeList(c['items'], IngestJob.fromJson) : null,
        total: asInt(c['total']),
      );
}

class IngestQualityOption {
  final String id;
  final String label;
  const IngestQualityOption({this.id = '', this.label = ''});
  factory IngestQualityOption.fromJson(Map<String, dynamic> c) =>
      IngestQualityOption(id: asStringOr(c['id'], ''), label: asStringOr(c['label'], ''));
}

class IngestRange {
  final double? min;
  final double? max;
  const IngestRange({this.min, this.max});
  factory IngestRange.fromJson(Map<String, dynamic> c) =>
      IngestRange(min: asDouble(c['min']), max: asDouble(c['max']));
}

class IngestLimits {
  final IngestRange? concurrency;
  final IngestRange? gapMs;
  final IngestRange? kugouGapMs;
  final IngestRange? kugouApiGapMs;
  const IngestLimits({this.concurrency, this.gapMs, this.kugouGapMs, this.kugouApiGapMs});
  factory IngestLimits.fromJson(Map<String, dynamic> c) => IngestLimits(
        concurrency: asMap(c['concurrency']) != null ? IngestRange.fromJson(asMap(c['concurrency'])!) : null,
        gapMs: asMap(c['gapMs']) != null ? IngestRange.fromJson(asMap(c['gapMs'])!) : null,
        kugouGapMs: asMap(c['kugouGapMs']) != null ? IngestRange.fromJson(asMap(c['kugouGapMs'])!) : null,
        kugouApiGapMs: asMap(c['kugouApiGapMs']) != null ? IngestRange.fromJson(asMap(c['kugouApiGapMs'])!) : null,
      );
}

class IngestSettings {
  final Map<String, String>? qualities;
  final Map<String, List<IngestQualityOption>>? options;
  final double? concurrency;
  final double? gapMs;
  final double? kugouGapMs;
  final double? kugouApiGapMs;
  final IngestLimits? limits;

  const IngestSettings({
    this.qualities,
    this.options,
    this.concurrency,
    this.gapMs,
    this.kugouGapMs,
    this.kugouApiGapMs,
    this.limits,
  });

  factory IngestSettings.fromJson(Map<String, dynamic> c) {
    Map<String, List<IngestQualityOption>>? opts;
    final rawOpts = asMap(c['options']);
    if (rawOpts != null) {
      opts = rawOpts.map((k, v) =>
          MapEntry(k, decodeList(v, IngestQualityOption.fromJson)));
    }
    Map<String, String>? quals;
    final rawQ = asMap(c['qualities']);
    if (rawQ != null) {
      quals = rawQ.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    }
    return IngestSettings(
      qualities: quals,
      options: opts,
      concurrency: asDouble(c['concurrency']),
      gapMs: asDouble(c['gapMs']),
      kugouGapMs: asDouble(c['kugouGapMs']),
      kugouApiGapMs: asDouble(c['kugouApiGapMs']),
      limits: asMap(c['limits']) != null ? IngestLimits.fromJson(asMap(c['limits'])!) : null,
    );
  }
}

class IngestBatchResult {
  final int? queued;
  final int? skipped;
  final int? unsupported;
  final int? retried;
  const IngestBatchResult({this.queued, this.skipped, this.unsupported, this.retried});
  factory IngestBatchResult.fromJson(Map<String, dynamic> c) => IngestBatchResult(
        queued: asInt(c['queued']),
        skipped: asInt(c['skipped']),
        unsupported: asInt(c['unsupported']),
        retried: asInt(c['retried']),
      );
  String get message {
    final parts = <String>[];
    if ((queued ?? 0) > 0) parts.add('已加入 $queued 首');
    if ((skipped ?? 0) > 0) parts.add('跳过 $skipped 首');
    if ((unsupported ?? 0) > 0) parts.add('不支持 $unsupported 首');
    return parts.isEmpty ? '没有可入库曲目' : parts.join('，');
  }
}
