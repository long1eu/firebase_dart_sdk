@TestOn('vm')
library;

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../support/rc_realtime_fakes.dart';
import '../support/rc_realtime_harness.dart';

/// Sends 1000 invalidations over 10 s (one chunk every 10 ms), the text of each from [message].
void storm(
  FakeAsync async,
  RealtimeConnection connection,
  String Function(int index) message,
) {
  for (int index = 0; index < 1000; index++) {
    connection.send(message(index));
    async.elapse(const Duration(milliseconds: 10));
  }
}

void main() {
  for (final double random in <double>[0.0, 0.5, 0.9999]) {
    test(
      '5.9.2 storm: 1000 invalidations of one version in 10 s -> at most 3 fetches and one '
      'update-not-fetched (random $random)',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async, random: random);
          // The server stays behind the announced version, so the chain ends stale.
          h.server.fetchAnswer = (FetchCall call) =>
              templateResponse(version: 1);
          final UpdateLog log = h.listen();
          storm(
            async,
            h.server.last,
            (int index) => '{"latestTemplateVersionNumber": "2"}',
          );
          h.elapseTo(const Duration(seconds: 30));

          expect(h.server.fetches.length, lessThanOrEqualTo(3));
          expect(
            log.codes.where((String code) => code == 'update-not-fetched'),
            hasLength(1),
          );
          expect(
            log.codes.where((String code) => code != 'update-not-fetched'),
            isEmpty,
          );
          expect(log.updates, isEmpty);
          expect(
            h.server.connections,
            hasLength(1),
            reason: 'the storm does not end the stream',
          );
          h.dispose();
        });
      },
    );
  }

  test('5.9.2 storm: 1000 invalidations of rising versions in 10 s -> at most 3 fetches and one '
      'update-not-fetched in the first 60 s, then one deferred chain', () {
    fakeAsync((FakeAsync async) {
      final RcHarness h = RcHarness(async);
      h.server.fetchAnswer = (FetchCall call) => templateResponse(version: 1);
      final UpdateLog log = h.listen();
      storm(
        async,
        h.server.last,
        (int index) => '{"latestTemplateVersionNumber": "${index + 2}"}',
      );
      // One chain at a time, and none for 60 s after it ends: the storm raises the target only.
      h.elapseTo(const Duration(seconds: 60));
      expect(h.server.fetches, hasLength(3));
      expect(
        log.codes.where((String code) => code == 'update-not-fetched'),
        hasLength(1),
      );

      // The target is still ahead of the fetched version at the 60 s mark: one deferred chain, then
      // nothing more (the storm is over).
      h.elapseTo(const Duration(minutes: 2));
      expect(
        <String?>[
          for (final FetchCall call in h.server.fetches) call.fetchType,
        ],
        <String>[
          'REALTIME/1',
          'REALTIME/2',
          'REALTIME/3',
          'REALTIME/1',
          'REALTIME/2',
          'REALTIME/3',
        ],
      );
      final Duration firstEnd = h.server.fetches[2].at.difference(rcEpoch);
      final Duration deferredStart = h.server.fetches[3].at.difference(rcEpoch);
      expect(
        deferredStart,
        greaterThanOrEqualTo(firstEnd + const Duration(seconds: 60)),
      );
      expect(
        log.codes.where((String code) => code == 'update-not-fetched'),
        hasLength(2),
      );
      expect(
        log.codes.where((String code) => code != 'update-not-fetched'),
        isEmpty,
      );
      expect(log.updates, isEmpty);
      h.dispose();
    });
  });
}
