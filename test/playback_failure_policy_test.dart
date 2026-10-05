import 'package:flutter_test/flutter_test.dart';
import 'package:musix/models/models.dart';

void main() {
  group('PlaybackFailurePolicy', () {
    test('selects the next track in queue order', () {
      expect(
        PlaybackFailurePolicy.nextIndex(
          order: const [0, 1, 2, 3],
          current: 1,
          failed: const {1},
          wrap: false,
        ),
        2,
      );
    });

    test('skips tracks that already failed', () {
      expect(
        PlaybackFailurePolicy.nextIndex(
          order: const [2, 0, 3, 1],
          current: 2,
          failed: const {2, 0},
          wrap: false,
        ),
        3,
      );
    });

    test('wraps only when repeat-all is enabled', () {
      expect(
        PlaybackFailurePolicy.nextIndex(
          order: const [0, 1, 2],
          current: 2,
          failed: const {2},
          wrap: false,
        ),
        isNull,
      );
      expect(
        PlaybackFailurePolicy.nextIndex(
          order: const [0, 1, 2],
          current: 2,
          failed: const {0, 2},
          wrap: true,
        ),
        1,
      );
    });

    test('stops after every candidate has failed', () {
      expect(
        PlaybackFailurePolicy.nextIndex(
          order: const [0, 1, 2],
          current: 1,
          failed: const {0, 1, 2},
          wrap: true,
        ),
        isNull,
      );
    });
  });

  group('PlaybackRecoveryPolicy', () {
    test('retries autoplay failures three times', () {
      expect(
          PlaybackRecoveryPolicy.canRetry(autoplay: true, attempt: 0), isTrue);
      expect(
          PlaybackRecoveryPolicy.canRetry(autoplay: true, attempt: 2), isTrue);
      expect(
          PlaybackRecoveryPolicy.canRetry(autoplay: true, attempt: 3), isFalse);
      expect(PlaybackRecoveryPolicy.canRetry(autoplay: false, attempt: 0),
          isFalse);
    });

    test('backs off before each retry', () {
      expect(PlaybackRecoveryPolicy.delayForAttempt(1),
          const Duration(seconds: 1));
      expect(PlaybackRecoveryPolicy.delayForAttempt(2),
          const Duration(seconds: 3));
      expect(PlaybackRecoveryPolicy.delayForAttempt(3),
          const Duration(seconds: 6));
    });
  });
}
