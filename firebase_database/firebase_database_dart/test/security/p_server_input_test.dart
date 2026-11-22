// Owner P. Threat model T11a and decisions section 6 at the level of PersistentConnection: a data
// message that the decoder marks as a protocol error closes the connection, is logged once at
// warning and reaches no delegate method; the reconnect waits for the backoff at its cap, so a
// server that sends a malformed message on every connection cannot make the client reconnect
// fast. A message that is merely unknown keeps the connection.
//
// The messages are raw JSON text, so that a non-finite number (`1e400`) can be sent; on the web
// such a number also passes `is int`, which the decoder covers.
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../util/persistent_connection_harness.dart';

/// The `d` of a data message, per family of malformed input.
const Map<String, List<String>> _malformed = <String, List<String>>{
  'bad request number': <String>[
    '{"r":-1,"b":{"s":"ok","d":null}}',
    '{"r":"1","b":{"s":"ok","d":null}}',
    '{"r":1.5,"b":{"s":"ok","d":null}}',
  ],
  'bad tag': <String>[
    '{"a":"d","b":{"p":"a","d":1,"t":-3}}',
    '{"a":"m","b":{"p":"a","d":{"b":1},"t":"7"}}',
    '{"a":"rm","b":{"p":"a","d":[{"m":1}],"t":2.5}}',
  ],
  'non-finite number': <String>[
    '{"a":"d","b":{"p":"a","d":1e400}}',
    '{"a":"d","b":{"p":"a","d":{"k":[-1e400]}}}',
    '{"a":"d","b":{"p":"a","d":1,"t":1e400}}',
    '{"r":1e400,"b":{"s":"ok","d":null}}',
  ],
  'bad path': <String>[
    '{"a":"d","b":{"p":"a/.b","d":1}}',
    '{"a":"d","b":{"p":"a#b","d":1}}',
    '{"a":"c","b":{"p":"a[0]"}}',
    '{"a":"rm","b":{"p":"a//b","d":[{"m":1}]}}',
    '{"a":"d","b":{"p":5,"d":1}}',
  ],
  'wrong type for data': <String>[
    '{"a":"d","b":"not an object"}',
    '{"a":5,"b":{}}',
    '{"error":5}',
    '{"a":"d","b":{"p":"a"}}',
    '{"a":"d","b":{"p":"a","d":{"k":{".sv":"timestamp"}}}}',
    '{"a":"c","b":{"p":"a","q":"all"}}',
    '{"a":"sd","b":{"msg":5}}',
  ],
  'bad merge': <String>[
    '{"a":"m","b":{"p":"a","d":[1,2]}}',
    '{"a":"m","b":{"p":"a","d":{"/x":1}}}',
    '{"a":"m","b":{"p":"a","d":{"x":{"a.b":1}}}}',
  ],
  'bad range merge': <String>[
    '{"a":"rm","b":{"p":"a","d":{"m":1}}}',
    '{"a":"rm","b":{"p":"a","d":[{"m":1,"x":2}]}}',
    '{"a":"rm","b":{"p":"a","d":[{"s":"b","m":1}]}}',
    '{"a":"rm","b":{"p":"a","d":[{"e":"b","m":1},{"m":2}]}}',
  ],
  'bad revoke': <String>[
    '{"a":"ac","b":{"s":5}}',
    '{"a":"ac","b":{"s":"invalid_token","d":7}}',
    '{"a":"apc","b":{"d":"no status"}}',
  ],
};

/// The delegate methods that carry server input; none may run for a malformed message.
const Set<String> _inputMethods = <String>{
  'dataUpdate',
  'rangeMergeUpdate',
  'authStatus',
  'appCheckStatus',
  'serverShutdown',
};

void main() {
  late PRig rig;

  tearDown(() => rig.connection.shutdown());

  _malformed.forEach((String family, List<String> messages) {
    group(family, () {
      for (final String message in messages) {
        test(
          '$message closes the connection and reaches no delegate',
          () async {
            rig = PRig();
            await rig.start();
            await rig.settle();
            final int callsBefore = rig.delegate.calls.length;

            rig.server.connector.last.serverText('{"t":"d","d":$message}');
            await until(() => rig.delegate.callsOf('disconnect').length == 1);
            await until(() => rig.connects == 2);

            // Breaks if the `case Ignored(isProtocolError: true)` branch of
            // PersistentConnection._onDataMessage does not call _protocolError.
            final List<String> after = rig.delegate.methods.sublist(
              callsBefore,
            );
            expect(after.where(_inputMethods.contains), isEmpty);
            expect(after.first, 'disconnect');
            expect(
              rig.logs.where(
                (String l) => l.startsWith('warning: protocol error'),
              ),
              hasLength(1),
            );
            expect(rig.logs.join('\n'), isNot(contains('Ignored a server')));
          },
        );
      }
    });
  });

  test('an unknown action is ignored and keeps the connection', () async {
    rig = PRig();
    await rig.start();
    rig.server.connector.last.serverText(
      '{"t":"d","d":{"a":"newer-server-action","b":{"p":"a"}}}',
    );
    rig.server.pushData('/a', 1);
    await until(() => rig.delegate.callsOf('dataUpdate').isNotEmpty);

    expect(rig.delegate.callsOf('disconnect'), isEmpty);
    expect(rig.server.connections, 1);
    expect(rig.logs.where((String l) => l.startsWith('warning:')), isEmpty);
  });

  test(
    'a server that sends a malformed message on every healthy connection gets the capped delay',
    () {
      fakeAsync((FakeAsync async) {
        final DateTime start = DateTime.utc(2026, 11, 22);
        rig = PRig(
          timings: shrunkTimings(
            reconnectMin: const Duration(milliseconds: 100),
            reconnectMax: const Duration(seconds: 2),
            // Zero: any established connection would reset the delay to 100 ms at its drop.
            reconnectResetAfter: Duration.zero,
          ),
          now: () => start.add(async.elapsed),
          elapsed: () => async.elapsed,
        );
        rig.connection.initialize();
        for (int n = 1; n <= 3; n++) {
          elapseUntil(async, () => rig.connects == n);
          // Two ok answers: the connection is healthy and established (T13).
          rig.answerCredentialsNow();
          async
            ..flushMicrotasks()
            ..elapse(const Duration(milliseconds: 1));
          rig.server.connector.last.serverText(
            '{"t":"d","d":{"a":"d","b":{"p":"a#b","d":1}}}',
          );
          elapseUntil(
            async,
            () => rig.delegate.callsOf('disconnect').length == n,
          );
        }
        elapseUntil(async, () => rig.attemptTimes.length == 4);

        final List<int> gaps = <int>[
          for (int i = 1; i < rig.attemptTimes.length; i++)
            (rig.attemptTimes[i] - rig.attemptTimes[i - 1]).inMilliseconds,
        ];
        // Breaks if _protocolError does not call _backoff.setToMax(): the established connection
        // would reset the bound to 100 ms.
        for (final int gap in gaps) {
          expect(gap, greaterThanOrEqualTo(1990), reason: '$gaps');
        }
        rig.connection.shutdown();
        async.flushMicrotasks();
      });
    },
  );
}
