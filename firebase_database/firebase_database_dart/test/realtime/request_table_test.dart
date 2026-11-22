// RequestTable: the link-silence rule (review H1) where the tests of replay_test.dart stop. Only an
// inbound frame moves the deadline; a new request, an answer or a clear never pushes it later.

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/realtime/request_table.dart';
import 'package:test/test.dart';

const Duration _timeout = Duration(seconds: 60);
const Duration _half = Duration(seconds: 30);
const Duration _ms = Duration(milliseconds: 1);
const Map<String, Object?> _ok = <String, Object?>{'s': 'ok'};

void main() {
  test(
    'a request added while the link is silent keeps the deadline of the first',
    () {
      fakeAsync((FakeAsync async) {
        int silences = 0;
        final RequestTable requests = RequestTable(
          timeout: _timeout,
          onSilence: () => silences++,
        )..add((_) {});
        async.elapse(_half);
        // A client that keeps writing on a dead link must still see the silence at 60 s.
        requests.add((_) {});
        async.elapse(_half - _ms);
        expect(silences, 0);
        async.elapse(_ms);

        expect(silences, 1);
        expect(requests.pending, 2);
        requests.clear();
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  test('steady writes every 30 s on a silent link do not hide the silence', () {
    fakeAsync((FakeAsync async) {
      final List<Duration> silences = <Duration>[];
      late final RequestTable requests;
      requests = RequestTable(
        timeout: _timeout,
        onSilence: () {
          silences.add(async.elapsed);
          requests.clear();
        },
      );
      for (int i = 0; i < 4; i++) {
        requests.add((_) {});
        async.elapse(_half);
      }

      // Cleared at 60 s; the requests added at 60 s and 90 s start a new deadline at 60 s.
      expect(silences, <Duration>[_timeout, _timeout * 2]);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test(
    'an answer alone does not move the deadline of the requests still waiting',
    () {
      fakeAsync((FakeAsync async) {
        int silences = 0;
        final RequestTable requests = RequestTable(
          timeout: _timeout,
          onSilence: () => silences++,
        );
        final int first = requests.add((_) {});
        requests.add((_) {});
        async.elapse(_half);
        expect(requests.complete(first, _ok), isTrue);
        async.elapse(_half);

        expect(silences, 1);
        expect(requests.pending, 1);
        requests.clear();
      });
    },
  );

  test(
    'a request added from inside an answer starts its deadline at that answer',
    () {
      fakeAsync((FakeAsync async) {
        int silences = 0;
        late final RequestTable requests;
        requests = RequestTable(timeout: _timeout, onSilence: () => silences++);
        final int first = requests.add((_) => requests.add((_) {}));
        async.elapse(_half);
        requests.complete(first, _ok);
        async.elapse(_timeout - _ms);
        expect(silences, 0);
        async.elapse(_ms);

        expect(silences, 1);
        requests.clear();
      });
    },
  );

  test(
    'the silence callback may clear the table (the owner closes the connection)',
    () {
      fakeAsync((FakeAsync async) {
        final List<Map<String, Object?>> answers = <Map<String, Object?>>[];
        late final RequestTable requests;
        requests = RequestTable(
          timeout: _timeout,
          onSilence: () => requests.clear(),
        );
        final int r = requests.add(answers.add);
        async.elapse(_timeout);

        expect(requests.pending, 0);
        expect(requests.complete(r, _ok), isFalse);
        expect(answers, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'numbers keep growing across a clear (a reconnect never reuses one)',
    () {
      final RequestTable requests = RequestTable(
        timeout: _timeout,
        onSilence: () {},
      );
      expect(requests.add((_) {}), 1);
      expect(requests.add(null), 2);
      requests.clear();
      expect(requests.add((_) {}), 3);
      requests.clear();
    },
  );
}
