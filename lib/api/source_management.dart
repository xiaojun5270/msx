import '../models/models.dart';
import 'api_client.dart';

/// Source-management + playback-session endpoints.
/// Mirrors Swift `SourceManagementAPI` (an APIClient extension).
extension SourceManagementAPI on APIClient {
  Future<SubstitutionOutcome> applySource({
    required Track original,
    required Track candidate,
    int? version,
  }) {
    final p = SourceSessionPolicy.pathComponent(original.platform);
    final i = SourceSessionPolicy.pathComponent(original.id);
    return postJson(
      '/api/track-overrides/$p/$i/apply',
      SubstitutionOutcome.fromJson,
      json: SourceRequestPayload.apply(original, candidate, version: version),
    );
  }

  Future<SourceOverrideContext> sourceContext(Track track) {
    final p = SourceSessionPolicy.pathComponent(track.platform);
    final i = SourceSessionPolicy.pathComponent(track.id);
    return getJson('/api/track-overrides/$p/$i/context', SourceOverrideContext.fromJson);
  }

  Future<SourceOverrideContext> sourceCandidates(Track track, {bool refresh = false}) {
    final p = SourceSessionPolicy.pathComponent(track.platform);
    final i = SourceSessionPolicy.pathComponent(track.id);
    return postJson(
      '/api/track-overrides/$p/$i/candidates',
      SourceOverrideContext.fromJson,
      json: {'payload': track.identityPayload(), 'refresh': refresh},
    );
  }

  Future<PlaybackSessionResponse> createPlaybackSession(
    Track track, {
    required String intentId,
    bool recover = false,
  }) {
    return postJson(
      '/api/playback/sessions',
      PlaybackSessionResponse.fromJson,
      json: SourceRequestPayload.playback(track, intentId, recover: recover),
    );
  }

  Future<PlaybackSessionResponse> pollPlaybackIntent(String intentId) {
    return getJson('/api/playback/intents/$intentId', PlaybackSessionResponse.fromJson);
  }

  Future<SourceSubstitutionRun> organizeSources({
    required List<Track> tracks,
    bool backgroundIngest = false,
    required String requestId,
  }) {
    return postJson(
      '/api/source-substitution/runs',
      SourceSubstitutionRun.fromJson,
      json: SourceRequestPayload.organize(tracks, backgroundIngest: backgroundIngest, requestId: requestId),
    );
  }
}
