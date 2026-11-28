@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/realtime/realtime_client.dart';
import 'package:firebase_remote_config_dart/src/realtime/updated_keys.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/rc_realtime_fakes.dart';
import '../support/rc_realtime_harness.dart';

/// [seconds] as a [Duration], fractions allowed.
Duration s(num seconds) => Duration(microseconds: (seconds * 1000000).round());

/// The transport table of 5.9.1, in seconds (entry `min(n, 9)`).
const List<int> transportTable = <int>[1, 2, 4, 8, 16, 32, 60, 120, 300];

/// Connection times of a client whose every attempt fails as a transport failure, jitter factor 1.
const List<int> transportTimes = <int>[
  0, 1, 3, 7, 15, 31, 63, 123, 243, 543, 843, 1143, 1443, 1743, //
  2043, 2343, 2643, 2943, 3243, 3543,
];

Future<http.StreamedResponse> drop(RealtimeConnection connection) =>
    connection.drop();

Future<http.StreamedResponse> accept(RealtimeConnection connection) =>
    connection.accept();

FirebaseInstallationsException installationsError(String code) =>
    FirebaseInstallationsException(code: code, message: 'fake $code');

void main() {
  group('5.9 open and close', () {
    test(
      '5.9 opens on the first listener and aborts at once on the last cancel (§6 row 4)',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          async.elapse(const Duration(minutes: 1));
          expect(
            h.server.connections,
            isEmpty,
            reason: 'nothing is sent without a listener',
          );

          final UpdateLog first = h.listen();
          final UpdateLog second = h.listen();
          expect(h.server.connections, hasLength(1));
          final RealtimeConnection connection = h.server.last;
          expect(connection.isOpen, isTrue);

          first.cancel();
          async.flushMicrotasks();
          expect(connection.aborted, isFalse, reason: 'one listener remains');

          second.cancel();
          async.flushMicrotasks();
          expect(
            connection.aborted,
            isTrue,
            reason: 'the last cancel aborts at once',
          );

          async.elapse(const Duration(hours: 1));
          expect(h.server.connections, hasLength(1));
          h.dispose();
        });
      },
    );

    test(
      '5.9 going to the background aborts at once; the foreground reopens',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.listen();
          final RealtimeConnection first = h.server.last;

          h.elapseTo(s(10));
          h.app.onBackgroundChanged.add(true);
          async.flushMicrotasks();
          expect(first.aborted, isTrue);

          h.elapseTo(const Duration(hours: 1));
          expect(
            h.server.connections,
            hasLength(1),
            reason: 'no connect in the background',
          );

          h.app.onBackgroundChanged.add(false);
          async.elapse(Duration.zero);
          expect(h.server.connections, hasLength(2));
          expect(h.server.last.isOpen, isTrue);
          h.dispose();
        });
      },
    );

    test(
      '5.9 background toggles keep the backoff and do not count as failures',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.realtimeAnswer = (RealtimeConnection c) => c.refuse(503);
          final UpdateLog log = h.listen();
          expect(h.server.connections, hasLength(1));

          h.elapseTo(s(30));
          h.app.onBackgroundChanged.add(true);
          async.flushMicrotasks();
          h.elapseTo(s(31));
          h.app.onBackgroundChanged.add(false);
          async.flushMicrotasks();

          h.elapseTo(s(119));
          expect(
            h.server.connections,
            hasLength(1),
            reason: 'first server failure waits 2 min',
          );
          h.elapseTo(s(120));
          expect(h.server.connections, hasLength(2));

          h.elapseTo(s(359));
          expect(
            h.server.connections,
            hasLength(2),
            reason: 'second server failure waits 4 min',
          );
          h.elapseTo(s(360));
          expect(h.server.connections, hasLength(3));
          expect(log.errors, isEmpty);
          h.dispose();
        });
      },
    );

    test('5.9 listener changes keep the backoff', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.server.realtimeAnswer = (RealtimeConnection c) => c.refuse(503);
        final UpdateLog first = h.listen();

        h.elapseTo(s(30));
        first.cancel();
        async.flushMicrotasks();
        h.elapseTo(s(31));
        h.listen();

        h.elapseTo(s(119));
        expect(h.server.connections, hasLength(1));
        h.elapseTo(s(120));
        expect(h.server.connections, hasLength(2));
        h.dispose();
      });
    });

    test('5.9 a hidden page keeps the stream closed (client constructor)', () {
      fakeAsync((FakeAsync async) {
        final DirectRealtime d = DirectRealtime(async);
        d.visibility.setHidden(true);
        async.flushMicrotasks();
        d.listen();
        async.elapse(const Duration(minutes: 1));
        expect(d.server.connections, isEmpty);

        d.visibility.setHidden(false);
        async.elapse(Duration.zero);
        expect(d.server.connections, hasLength(1));

        d.visibility.setHidden(true);
        async.flushMicrotasks();
        expect(d.server.last.aborted, isTrue);
        d.dispose();
      });
    });

    test(
      '5.9 the replayed network seed is skipped; a later true connects at once',
      () {
        fakeAsync((FakeAsync async) {
          final DirectRealtime d = DirectRealtime(async, seedNetwork: false);
          d.server.realtimeAnswer = (RealtimeConnection c) => c.refuse(503);
          d.listen();
          expect(d.server.connections, hasLength(1));

          d.elapseTo(s(10));
          d.network.add(true); // The first event: the value replayed on listen.
          async.elapse(Duration.zero);
          expect(
            d.server.connections,
            hasLength(1),
            reason: 'the seed must not end the backoff',
          );

          d.elapseTo(s(20));
          d.network.add(false);
          async.elapse(Duration.zero);
          expect(d.server.connections, hasLength(1));

          d.network.add(true);
          async.elapse(Duration.zero);
          expect(d.server.connections, hasLength(2));
          expect(d.server.connectionTimes.last, s(20));
          d.dispose();
        });
      },
    );
  });

  group('5.9.1 backoff', () {
    test(
      '5.9.1 accept-and-close over 1 h stays within the tables (§6 row 6)',
      () {
        fakeAsync((FakeAsync async) {
          final DirectRealtime d = DirectRealtime(async);
          d.server.realtimeAnswer = (RealtimeConnection c) =>
              c.acceptAndClose();
          final UpdateLog log = d.listen();
          d.elapseTo(const Duration(hours: 1));
          expect(d.server.connectionTimes, <Duration>[
            for (final int t in transportTimes) s(t),
          ]);
          expect(log.codes, <String>['stream-error']);
          d.dispose();
        });
      },
    );

    for (final double random in <double>[0.0, 0.9999]) {
      test(
        '5.9.1 transport waits stay within table x [0.5, 1.5) (random $random)',
        () {
          fakeAsync((FakeAsync async) {
            final DirectRealtime d = DirectRealtime(async, random: random);
            d.server.realtimeAnswer = (RealtimeConnection c) =>
                c.acceptAndClose();
            d.listen();
            d.elapseTo(const Duration(hours: 1));
            final List<Duration> times = d.server.connectionTimes;
            expect(times.length, greaterThan(10));
            for (int i = 1; i < times.length; i++) {
              final Duration gap = times[i] - times[i - 1];
              final int base = transportTable[(i < 9 ? i : 9) - 1];
              expect(
                gap,
                greaterThanOrEqualTo(s(base * 0.5)),
                reason: 'gap $i',
              );
              expect(gap, lessThanOrEqualTo(s(base * 1.5)), reason: 'gap $i');
              expect(gap, lessThanOrEqualTo(s(450)));
            }
            d.dispose();
          });
        },
      );
    }

    test('5.9.1 a connection open 60 s is a success and resets the counts', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        int answered = 0;
        h.server.realtimeAnswer = (RealtimeConnection c) {
          answered++;
          return answered <= 3 || answered == 5 ? c.drop() : c.accept();
        };
        final UpdateLog log = h.listen();
        h.elapseTo(s(70));
        expect(h.server.connectionTimes, <Duration>[s(0), s(1), s(3), s(7)]);
        h.server.last.end();
        h.elapseTo(s(100));
        // A clean end waits the 1 s floor; the next failure is the first one again (1 s).
        expect(h.server.connectionTimes, <Duration>[
          s(0),
          s(1),
          s(3),
          s(7),
          s(71),
          s(72),
        ]);
        expect(log.errors, isEmpty);
        h.dispose();
      });
    });

    test(
      '5.9.1 a connection that ends after 59 s is a transport failure; messages do not count',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          int answered = 0;
          h.server.realtimeAnswer = (RealtimeConnection c) {
            answered++;
            return answered <= 3 ? c.drop() : c.accept();
          };
          h.listen();
          h.elapseTo(s(30));
          h.server.last.send('[{"latestTemplateVersionNumber": "0"}');
          h.elapseTo(s(66));
          h.server.last.end();
          h.elapseTo(s(73));
          expect(h.server.connections, hasLength(4));
          h.elapseTo(s(74));
          // The fourth consecutive transport failure waits 8 s.
          expect(h.server.connectionTimes.last, s(74));
          h.dispose();
        });
      },
    );

    test(
      '5.9.1 offline recovery: the first connect after the network returns is within 5 minutes (§6 row 9)',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.realtimeAnswer = drop;
          h.listen();
          h.elapseTo(const Duration(hours: 1));
          h.server.realtimeAnswer = accept;
          final int before = h.server.connections.length;
          h.elapseTo(const Duration(hours: 1) + s(300));
          expect(h.server.connections.length, greaterThan(before));
          final RealtimeConnection back = h.server.connections[before];
          expect(
            back.openedAt.difference(rcEpoch) - const Duration(hours: 1),
            lessThanOrEqualTo(s(300)),
          );
          expect(back.isOpen, isTrue);
          h.dispose();
        });
      },
    );

    test(
      '5.9.1 eight failures emit one stream-error, reconnecting continues (§6 row 7)',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.realtimeAnswer = drop;
          final UpdateLog log = h.listen();
          h.elapseTo(s(122));
          expect(h.server.connections, hasLength(7));
          expect(log.errors, isEmpty);

          h.elapseTo(s(123));
          expect(log.codes, <String>['stream-error']);

          h.elapseTo(s(2000));
          expect(log.codes, <String>[
            'stream-error',
          ], reason: 'one error until a success');
          expect(
            h.server.connections,
            hasLength(14),
            reason: 'it keeps reconnecting',
          );
          expect(log.done, isFalse);

          h.server.realtimeAnswer = accept;
          h.elapseTo(s(2043));
          expect(h.server.last.isOpen, isTrue);
          h.elapseTo(s(2110));
          h.server.realtimeAnswer = drop;
          h.server.last.end();
          h.elapseTo(s(3000));
          expect(log.codes, <String>[
            'stream-error',
            'stream-error',
          ], reason: 'a success re-arms it');
          expect(log.done, isFalse);
          h.dispose();
        });
      },
    );

    test('5.9.1 server and transport failures add up to eight', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        int answered = 0;
        h.server.realtimeAnswer = (RealtimeConnection c) {
          answered++;
          return answered <= 4 ? c.refuse(503) : c.drop();
        };
        final UpdateLog log = h.listen();
        h.elapseTo(s(1806));
        expect(h.server.connectionTimes, <Duration>[
          s(0),
          s(120),
          s(360),
          s(840),
          s(1800),
          s(1801),
          s(1803),
        ]);
        expect(log.errors, isEmpty);
        h.elapseTo(s(1807));
        expect(log.codes, <String>['stream-error']);
        h.dispose();
      });
    });

    test('5.9.1 network regained connects at once, subject to the floor', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.server.realtimeAnswer = drop;
        h.listen();
        h.elapseTo(s(600));
        expect(
          h.server.connectionTimes.last,
          s(543),
          reason: 'next attempt due at 843 s',
        );

        h.app.onNetworkConnected.add(false);
        async.elapse(Duration.zero);
        expect(h.server.connections, hasLength(10));

        h.app.onNetworkConnected.add(true);
        async.elapse(Duration.zero);
        expect(h.server.connections, hasLength(11));
        expect(h.server.connectionTimes.last, s(600));

        // Right after that failure, a regained network still waits the 1 s floor.
        h.elapseTo(s(600.2));
        h.app.onNetworkConnected.add(true);
        h.elapseTo(s(600.999));
        expect(h.server.connections, hasLength(11));
        h.elapseTo(s(601));
        expect(h.server.connections, hasLength(12));
        h.dispose();
      });
    });

    test('5.9.1 403 gives the server text and stops until a new listener', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.server.realtimeAnswer = (RealtimeConnection c) => c.refuse(
          403,
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 403,
              'message':
                  'Firebase Remote Config Realtime API has not been used in project 1234567890 '
                  'before or it is disabled.',
              'status': 'PERMISSION_DENIED',
            },
          }),
        );
        final UpdateLog log = h.listen();
        expect(log.errors, hasLength(1));
        final FirebaseRemoteConfigException error =
            log.errors.single as FirebaseRemoteConfigException;
        expect(error.code, 'stream-error');
        expect(error.httpStatus, 403);
        expect(error.serverStatus, 'PERMISSION_DENIED');
        expect(error.serverMessage, contains('has not been used in project'));

        h.elapseTo(const Duration(hours: 48));
        expect(h.server.connections, hasLength(1));
        expect(log.done, isFalse);
        expect(log.errors, hasLength(1));

        h.server.realtimeAnswer = accept;
        h.listen();
        expect(h.server.connections, hasLength(2));
        expect(h.server.last.isOpen, isTrue);
        h.dispose();
      });
    });

    test('5.9.1 a stop leaves the failure counts unchanged', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        int answered = 0;
        h.server.realtimeAnswer = (RealtimeConnection c) {
          answered++;
          return switch (answered) {
            1 || 3 => c.refuse(503),
            2 => c.refuse(403),
            _ => c.accept(),
          };
        };
        final UpdateLog log = h.listen();
        h.elapseTo(s(150));
        expect(log.codes, <String>['stream-error']);
        h.elapseTo(s(200));
        h.listen();
        h.elapseTo(s(600));
        // Second server failure: 4 min. Reset counts would give 2 min, a counted stop 8 min.
        expect(h.server.connectionTimes, <Duration>[
          s(0),
          s(120),
          s(200),
          s(440),
        ]);
        h.dispose();
      });
    });

    for (final int status in <int>[408, 429, 502, 503, 504]) {
      test('5.9.1 HTTP $status is a server failure (2 min)', () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.realtimeAnswer = (RealtimeConnection c) => c.refuse(status);
          final UpdateLog log = h.listen();
          h.elapseTo(s(119));
          expect(h.server.connections, hasLength(1));
          h.elapseTo(s(120));
          expect(h.server.connections, hasLength(2));
          expect(log.errors, isEmpty);
          h.dispose();
        });
      });
    }

    for (final int status in <int>[400, 401, 404, 409, 500, 501]) {
      test('5.9.1 HTTP $status stops with stream-error', () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.realtimeAnswer = (RealtimeConnection c) => c.refuse(status);
          final UpdateLog log = h.listen();
          h.elapseTo(const Duration(hours: 24));
          expect(h.server.connections, hasLength(1));
          expect(log.codes, <String>['stream-error']);
          expect(
            (log.errors.single as FirebaseRemoteConfigException).httpStatus,
            status,
          );
          h.dispose();
        });
      });
    }

    for (final String code in <String>[
      'network-error',
      'unavailable',
      'invalid-response',
      'installation-not-found',
    ]) {
      test('5.9.1 Installations $code is a transport failure (1 s)', () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.installations.errors.add(installationsError(code));
          final UpdateLog log = h.listen();
          expect(h.server.connections, isEmpty);
          h.elapseTo(s(0.999));
          expect(h.installations.callTimes, hasLength(1));
          h.elapseTo(s(1));
          expect(h.installations.callTimes, hasLength(2));
          expect(h.server.connections, hasLength(1));
          expect(log.errors, isEmpty);
          h.dispose();
        });
      });
    }

    test(
      '5.9.1 Installations too-many-requests is a server failure (2 min)',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.installations.errors.add(installationsError('too-many-requests'));
          final UpdateLog log = h.listen();
          h.elapseTo(s(119));
          expect(h.installations.callTimes, hasLength(1));
          h.elapseTo(s(120));
          expect(h.server.connections, hasLength(1));
          expect(log.errors, isEmpty);
          h.dispose();
        });
      },
    );

    for (final String code in <String>['bad-config', 'storage-error']) {
      test('5.9.1 Installations $code stops until a new listener', () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          final FirebaseInstallationsException cause = installationsError(code);
          h.installations.alwaysThrow = cause;
          final UpdateLog log = h.listen();
          expect(log.codes, <String>['stream-error']);
          expect(
            (log.errors.single as FirebaseRemoteConfigException).cause,
            same(cause),
          );

          h.elapseTo(const Duration(hours: 24));
          expect(h.installations.callTimes, hasLength(1));
          expect(log.done, isFalse);

          h.installations.alwaysThrow = null;
          h.listen();
          expect(h.installations.callTimes, hasLength(2));
          expect(h.server.connections, hasLength(1));
          h.dispose();
        });
      });
    }

    test('5.9.1 Installations installations-closed ends the stream', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.installations.alwaysThrow = installationsError(
          'installations-closed',
        );
        final UpdateLog log = h.listen();
        expect(log.done, isTrue);
        expect(log.errors, isEmpty);

        h.elapseTo(const Duration(hours: 1));
        expect(h.installations.callTimes, hasLength(1));
        final UpdateLog later = h.listen();
        expect(later.done, isTrue);
        expect(h.installations.callTimes, hasLength(1));
        h.dispose();
      });
    });

    test(
      '5.9.1 watchdog: 330 s without a byte ends the connection as a clean end (§6 row 8)',
      () {
        fakeAsync((FakeAsync async) {
          final DirectRealtime d = DirectRealtime(async);
          final UpdateLog log = d.listen();
          final RealtimeConnection first = d.server.last;
          d.elapseTo(s(329));
          expect(first.aborted, isFalse);
          d.elapseTo(s(330));
          expect(first.aborted, isTrue);
          d.elapseTo(s(330.999));
          expect(d.server.connections, hasLength(1));
          d.elapseTo(s(331));
          expect(
            d.server.connections,
            hasLength(2),
            reason: 'a clean end waits only the floor',
          );
          expect(log.errors, isEmpty);
          d.dispose();
        });
      },
    );

    test('5.9.1 watchdog: each byte restarts the 330 s', () {
      fakeAsync((FakeAsync async) {
        final DirectRealtime d = DirectRealtime(async);
        d.listen();
        final RealtimeConnection first = d.server.last;
        d.elapseTo(s(300));
        first.send('\n');
        d.elapseTo(s(629));
        expect(first.aborted, isFalse);
        d.elapseTo(s(630));
        expect(first.aborted, isTrue);
        d.dispose();
      });
    });
  });

  group('5.9 messages', () {
    test('5.9 three invalid messages end the connection as a failure', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        final UpdateLog log = h.listen();
        final RealtimeConnection first = h.server.last;
        first.send('{not json}');
        async.flushMicrotasks();
        first.send('{"latestTemplateVersionNumber": true}');
        async.flushMicrotasks();
        expect(log.codes, <String>[
          'update-message-invalid',
          'update-message-invalid',
        ]);
        expect(first.aborted, isFalse);

        first.send('[{"featureDisabled": "yes"}]');
        async.flushMicrotasks();
        expect(log.codes, hasLength(3));
        expect(log.codes.toSet(), <String>{'update-message-invalid'});
        expect(first.aborted, isTrue);

        h.elapseTo(s(1));
        expect(
          h.server.connections,
          hasLength(2),
          reason: 'a transport failure waits 1 s',
        );
        final RealtimeConnection second = h.server.last;
        second.send('{x}{y}');
        async.flushMicrotasks();
        expect(second.aborted, isFalse, reason: 'the count is per connection');
        expect(log.done, isFalse);
        h.dispose();
      });
    });

    test(
      '5.9 more than 16 KiB without a closing brace is one invalid message and a failure',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          final UpdateLog log = h.listen();
          final RealtimeConnection first = h.server.last;
          first.send('{${'a' * (16 * 1024 + 1)}');
          async.flushMicrotasks();
          expect(log.codes, <String>['update-message-invalid']);
          expect(first.aborted, isTrue);
          h.elapseTo(s(1));
          expect(h.server.connections, hasLength(2));
          h.dispose();
        });
      },
    );

    test(
      '5.9.3 featureDisabled ends every listener and disables realtime for the instance',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          final UpdateLog a = h.listen();
          final UpdateLog b = h.listen();
          final RealtimeConnection connection = h.server.last;
          connection.send(
            '{"featureDisabled": true, "latestTemplateVersionNumber": "5"}',
          );
          async.flushMicrotasks();
          for (final UpdateLog log in <UpdateLog>[a, b]) {
            expect(log.codes, <String>['realtime-unavailable']);
            expect(log.done, isTrue);
          }
          expect(connection.aborted, isTrue);

          h.elapseTo(const Duration(hours: 24));
          expect(h.server.connections, hasLength(1));
          expect(
            h.server.fetches,
            isEmpty,
            reason: 'the rest of the message is ignored',
          );

          final UpdateLog later = h.listen();
          expect(later.codes, <String>['realtime-unavailable']);
          expect(later.done, isTrue);
          expect(h.server.connections, hasLength(1));
          h.dispose();
        });
      },
    );

    test('5.9 retryIntervalSeconds delays the next connect', () {
      fakeAsync((FakeAsync async) {
        final DirectRealtime d = DirectRealtime(async);
        d.listen();
        d.server.last.send('{"retryIntervalSeconds": 600}');
        d.elapseTo(s(10));
        d.server.last.send('{"retryIntervalSeconds": 100}');
        d.elapseTo(s(61));
        d.server.last.end();
        d.elapseTo(s(599));
        expect(
          d.server.connections,
          hasLength(1),
          reason: 'a shorter interval does not shorten it',
        );
        d.elapseTo(s(600));
        expect(d.server.connections, hasLength(2));
        d.dispose();
      });
    });

    test(
      '5.9 retryIntervalSeconds is capped at 24 h; no timer is further ahead',
      () {
        fakeAsync((FakeAsync async) {
          final DirectRealtime d = DirectRealtime(async);
          d.listen();
          d.server.last.send('{"retryIntervalSeconds": 2147483647}');
          d.elapseTo(s(61));
          d.server.last.end();
          async.flushMicrotasks();
          expect(async.pendingTimers, isNotEmpty);
          for (final FakeTimer timer in async.pendingTimers) {
            expect(
              timer.duration,
              lessThanOrEqualTo(const Duration(hours: 24)),
            );
          }
          d.elapseTo(const Duration(hours: 24) - s(1));
          expect(d.server.connections, hasLength(1));
          d.elapseTo(const Duration(hours: 24));
          expect(d.server.connections, hasLength(2));
          d.dispose();
        });
      },
    );

    for (final String value in <String>['-5', '0', '"abc"', '1.5']) {
      test('5.9 retryIntervalSeconds $value is ignored', () {
        fakeAsync((FakeAsync async) {
          final DirectRealtime d = DirectRealtime(async);
          final UpdateLog log = d.listen();
          d.server.last.send('{"retryIntervalSeconds": $value}');
          d.elapseTo(s(61));
          d.server.last.end();
          d.elapseTo(s(62));
          expect(d.server.connections, hasLength(2));
          expect(log.errors, isEmpty);
          d.dispose();
        });
      });
    }
  });

  group('5.9.2 auto-fetch', () {
    test(
      '5.9.2 fetches at version 0 after the random wait and reports the keys (§6 row 3)',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.fetchAnswer = (FetchCall call) => templateResponse(
            version: 1,
            entries: const <String, String>{
              'welcome': 'hello',
              'color': 'blue',
            },
          );
          final UpdateLog log = h.listen();
          expect(h.server.last.body['lastKnownVersionNumber'], '0');

          h.server.last.send('{"latestTemplateVersionNumber": "1"}');
          async.flushMicrotasks();
          expect(
            h.server.fetches,
            isEmpty,
            reason: 'each attempt waits 0-3 s first',
          );

          h.elapseTo(s(1.5));
          expect(h.server.fetches, hasLength(1));
          expect(h.server.fetches.single.fetchType, 'REALTIME/1');
          expect(log.updates, hasLength(1));
          expect(log.updates.single.updatedKeys, <String>{'welcome', 'color'});
          expect(h.remoteConfig.info.fetchedTemplateVersion, 1);
          expect(
            h.remoteConfig.getString('welcome'),
            'default',
            reason: 'fetched, not activated',
          );

          h.server.last.send('{"latestTemplateVersionNumber": 1}');
          h.elapseTo(s(20));
          expect(
            h.server.fetches,
            hasLength(1),
            reason: 'not newer than the fetched version',
          );
          h.dispose();
        });
      },
    );

    test(
      '5.9.4 the update names the keys that differ from the active template',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.fetchAnswer = (FetchCall call) => templateResponse(
            version: 1,
            entries: const <String, String>{
              'welcome': 'hello',
              'color': 'blue',
            },
          );
          unawaited(
            h.remoteConfig.fetchAndActivate(
              minimumFetchInterval: Duration.zero,
            ),
          );
          async.flushMicrotasks();
          expect(h.remoteConfig.info.activeTemplateVersion, 1);

          h.server.fetchAnswer = (FetchCall call) => templateResponse(
            version: 2,
            entries: const <String, String>{'welcome': 'hello', 'color': 'red'},
          );
          final UpdateLog log = h.listen();
          expect(h.server.last.body['lastKnownVersionNumber'], '1');
          h.server.last.send('{"latestTemplateVersionNumber": "2"}');
          h.elapseTo(s(5));
          expect(log.updates.single.updatedKeys, <String>{'color'});
          h.dispose();
        });
      },
    );

    test(
      '5.9.2 a failed auto-fetch is reported as update-not-fetched (§6 row 10)',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.fetchAnswer = (FetchCall call) => http.Response('{}', 500);
          final UpdateLog log = h.listen();
          h.server.last.send('{"latestTemplateVersionNumber": "1"}');
          h.elapseTo(s(20));
          expect(h.server.fetches, hasLength(1));
          expect(log.codes, <String>['update-not-fetched']);
          final Object? cause =
              (log.errors.single as FirebaseRemoteConfigException).cause;
          expect(
            cause,
            isA<FirebaseRemoteConfigException>().having(
              (e) => e.code,
              'code',
              'fetch-status',
            ),
          );
          expect(log.updates, isEmpty);
          h.dispose();
        });
      },
    );

    test('5.9.2 a throttled auto-fetch is reported as update-not-fetched', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.server.fetchAnswer = (FetchCall call) => http.Response('{}', 429);
        final UpdateLog log = h.listen();
        h.server.last.send('{"latestTemplateVersionNumber": "1"}');
        h.elapseTo(s(20));
        expect(log.codes, <String>['update-not-fetched']);
        final Object? cause =
            (log.errors.single as FirebaseRemoteConfigException).cause;
        expect(
          cause,
          isA<FirebaseRemoteConfigException>().having(
            (e) => e.code,
            'code',
            'fetch-throttle',
          ),
        );
        h.dispose();
      });
    });

    test(
      '5.9.2 a chain that stays stale makes three attempts and one update-not-fetched',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.fetchAnswer = (FetchCall call) =>
              templateResponse(version: 1);
          final UpdateLog log = h.listen();
          h.server.last.send('{"latestTemplateVersionNumber": "2"}');
          h.elapseTo(s(20));
          expect(
            <String?>[
              for (final FetchCall call in h.server.fetches) call.fetchType,
            ],
            <String>['REALTIME/1', 'REALTIME/2', 'REALTIME/3'],
          );
          expect(
            <Duration>[
              for (final FetchCall call in h.server.fetches)
                call.at.difference(rcEpoch),
            ],
            <Duration>[s(1.5), s(3), s(4.5)],
          );
          expect(log.codes, <String>['update-not-fetched']);
          expect(
            (log.errors.single as FirebaseRemoteConfigException).cause,
            isNull,
          );
          expect(log.updates, isEmpty);
          h.dispose();
        });
      },
    );

    test('5.9.2 an invalidation during a chain raises its target', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.server.fetchAnswer = (FetchCall call) => templateResponse(version: 3);
        final UpdateLog log = h.listen();
        h.server.last.send('{"latestTemplateVersionNumber": "2"}');
        h.elapseTo(s(1));
        h.server.last.send('{"latestTemplateVersionNumber": "3"}');
        h.elapseTo(s(20));
        expect(h.server.fetches, hasLength(1));
        expect(log.updates, hasLength(1));
        expect(log.errors, isEmpty);
        h.dispose();
      });
    });

    test('5.9.2 (A19, A25) a repeat announcement inside the 60 s cool-down schedules the deferred '
        'chain, which runs when the cool-down ends', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.server.fetchAnswer = (FetchCall call) => templateResponse(version: 1);
        final UpdateLog log = h.listen();
        h.server.last.send('{"latestTemplateVersionNumber": "2"}');
        h.elapseTo(s(10));
        expect(h.server.fetches, hasLength(3));
        expect(log.codes, <String>['update-not-fetched']);

        // The stale chain ended at 4.5 s; its cool-down ends at 64.5 s. The same version again at
        // 10 s is not ignored: it schedules the deferred chain, whose first attempt follows the
        // 1.5 s wait after the cool-down.
        h.server.last.send('{"latestTemplateVersionNumber": "2"}');
        h.elapseTo(s(65.999));
        expect(
          h.server.fetches,
          hasLength(3),
          reason: 'nothing runs during the cool-down',
        );
        h.elapseTo(s(66));
        expect(h.server.fetches, hasLength(4));
        expect(h.server.fetches.last.fetchType, 'REALTIME/1');

        h.elapseTo(s(200));
        expect(
          <Duration>[
            for (final FetchCall call in h.server.fetches.skip(3))
              call.at.difference(rcEpoch),
          ],
          <Duration>[s(66), s(67.5), s(69)],
        );
        expect(log.codes, <String>['update-not-fetched', 'update-not-fetched']);
        h.dispose();
      });
    });

    test(
      '5.9.2 a higher target after a stale chain waits for the 60 s cool-down, then one chain runs',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.fetchAnswer = (FetchCall call) =>
              templateResponse(version: 1);
          final UpdateLog log = h.listen();
          h.server.last.send('{"latestTemplateVersionNumber": "2"}');
          h.elapseTo(s(10));
          expect(h.server.fetches, hasLength(3));

          // Higher targets during the cool-down (until 64.5 s) raise one deferred chain.
          h.server.last.send('{"latestTemplateVersionNumber": "3"}');
          h.elapseTo(s(20));
          h.server.last.send('{"latestTemplateVersionNumber": "4"}');
          h.elapseTo(s(65.9));
          expect(h.server.fetches, hasLength(3));

          h.elapseTo(s(66));
          expect(h.server.fetches, hasLength(4));
          expect(h.server.fetches.last.fetchType, 'REALTIME/1');

          h.elapseTo(s(200));
          expect(
            <Duration>[
              for (final FetchCall call in h.server.fetches.skip(3))
                call.at.difference(rcEpoch),
            ],
            <Duration>[s(66), s(67.5), s(69)],
          );
          expect(log.codes, <String>[
            'update-not-fetched',
            'update-not-fetched',
          ]);
          expect(log.updates, isEmpty);
          h.dispose();
        });
      },
    );

    test(
      '5.9.2 (A19) after an up-to-date chain a higher announcement starts a chain at once',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.fetchAnswer = (FetchCall call) =>
              templateResponse(version: 2);
          final UpdateLog log = h.listen();
          h.server.last.send('{"latestTemplateVersionNumber": "2"}');
          h.elapseTo(s(1.5));
          expect(h.server.fetches, hasLength(1));
          expect(log.updates, hasLength(1));

          // The chain ended up to date at 1.5 s: it leaves no cool-down, so version 3 starts a
          // chain at once (its attempt after the 1.5 s wait, at 3 s).
          h.server.fetchAnswer = (FetchCall call) => templateResponse(
            version: 3,
            entries: const <String, String>{'welcome': 'hey'},
          );
          h.server.last.send('{"latestTemplateVersionNumber": "3"}');
          h.elapseTo(s(2.999));
          expect(h.server.fetches, hasLength(1));
          h.elapseTo(s(3));
          expect(h.server.fetches, hasLength(2));
          expect(h.remoteConfig.info.fetchedTemplateVersion, 3);
          expect(log.updates, hasLength(2));

          // The app's own fetch afterwards is a BASE fetch; no chain is left to run.
          unawaited(h.remoteConfig.fetch(minimumFetchInterval: Duration.zero));
          async.flushMicrotasks();

          h.elapseTo(s(200));
          expect(
            <String?>[
              for (final FetchCall call in h.server.fetches) call.fetchType,
            ],
            <String>['REALTIME/1', 'REALTIME/1', 'BASE/1'],
          );
          expect(log.errors, isEmpty);
          h.dispose();
        });
      },
    );

    test(
      '5.9.2 (A12) after a stale chain the deferred chain is dropped when the target is no longer '
      'ahead',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.fetchAnswer = (FetchCall call) =>
              templateResponse(version: 1);
          final UpdateLog log = h.listen();
          h.server.last.send('{"latestTemplateVersionNumber": "2"}');
          h.elapseTo(s(10));
          expect(h.server.fetches, hasLength(3));

          // The stale chain ended at 4.5 s: version 3 waits for the cool-down (64.5 s).
          h.server.last.send('{"latestTemplateVersionNumber": "3"}');
          h.elapseTo(s(20));
          expect(h.server.fetches, hasLength(3));

          // The app's own fetch gets version 3 before the cool-down ends.
          h.server.fetchAnswer = (FetchCall call) =>
              templateResponse(version: 3);
          unawaited(h.remoteConfig.fetch(minimumFetchInterval: Duration.zero));
          async.flushMicrotasks();
          expect(h.remoteConfig.info.fetchedTemplateVersion, 3);

          h.elapseTo(s(200));
          expect(
            <String?>[
              for (final FetchCall call in h.server.fetches) call.fetchType,
            ],
            <String>['REALTIME/1', 'REALTIME/2', 'REALTIME/3', 'BASE/1'],
          );
          expect(log.codes, <String>['update-not-fetched']);
          h.dispose();
        });
      },
    );
  });

  group('5.9.5 FID change', () {
    test('5.9.5 an FID change reconnects an open stream with the new FID', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.listen();
        final RealtimeConnection first = h.server.last;
        expect(first.body['appInstanceId'], rcFirstFid);

        h.elapseTo(s(10));
        h.installations.changeId(rcSecondFid);
        async.flushMicrotasks();
        expect(first.aborted, isTrue);
        h.elapseTo(s(10.999));
        expect(h.server.connections, hasLength(1));
        h.elapseTo(s(11));
        expect(h.server.connections, hasLength(2));
        expect(h.server.last.body['appInstanceId'], rcSecondFid);
        h.dispose();
      });
    });

    test('5.9.5 an FID change without a listener sends nothing', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.installations.changeId(rcSecondFid);
        h.elapseTo(const Duration(minutes: 5));
        expect(h.server.connections, isEmpty);
        h.dispose();
      });
    });
  });

  group('5.9 project number', () {
    String? numberOf(String appId, [String? sender]) => projectNumberOf(
      FirebaseOptions(apiKey: 'k', appId: appId, messagingSenderId: sender),
    );

    test('5.9 project number derivation and fallback table', () {
      expect(numberOf('1:1234567890:web:abc'), '1234567890');
      expect(
        numberOf('1:1234567890:android:abc'),
        '1234567890',
        reason: 'no platform-tag restriction',
      );
      expect(
        numberOf('1:1234567890:ios:abc', '999'),
        '1234567890',
        reason: 'appId wins',
      );
      expect(numberOf('1:abc:web:x', '555'), '555');
      expect(numberOf('1:12a4:web:x', '555'), '555');
      expect(numberOf('1::web:x', '42'), '42');
      expect(numberOf('nocolons', '77'), '77');
      expect(numberOf('1:abc:web:x'), isNull);
      expect(numberOf('1:abc:web:x', 'abc'), isNull);
      expect(numberOf('1:abc:web:x', ''), isNull);
      expect(numberOf('1:-12:web:x', '+12'), isNull);
    });

    test('5.9 the request goes to the derived project number', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.listen();
        final Uri url = h.server.last.request.url;
        expect(url.host, rcRealtimeOrigin.host);
        expect(
          url.path,
          '/v1/projects/1234567890/namespaces/firebase:streamFetchInvalidations',
        );
        expect(h.server.last.body['project'], '1234567890');
        h.dispose();
      });
    });

    test('5.9 falls back to messagingSenderId', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(
          async,
          options: const FirebaseOptions(
            apiKey: 'AIzaSyRealtimeTestKey0000000000000000000',
            appId: '1:notdigits:web:abc',
            projectId: 'demo-realtime',
            messagingSenderId: '555',
          ),
        );
        h.listen();
        expect(
          h.server.last.request.url.path,
          '/v1/projects/555/namespaces/firebase:streamFetchInvalidations',
        );
        expect(h.server.last.body['project'], '555');
        h.dispose();
      });
    });

    test(
      '5.9 without a project number a subscriber gets stream-error naming the option',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(
            async,
            options: const FirebaseOptions(
              apiKey: 'AIzaSyRealtimeTestKey0000000000000000000',
              appId: '1:notdigits:web:abc',
              projectId: 'demo-realtime',
            ),
          );
          final UpdateLog log = h.listen();
          expect(log.codes, <String>['stream-error']);
          expect(
            (log.errors.single as FirebaseRemoteConfigException).message,
            contains('messagingSenderId'),
          );
          h.elapseTo(const Duration(hours: 24));
          expect(h.server.connections, isEmpty);
          // The project number is checked before Installations is asked for a token.
          expect(h.installations.callTimes, isEmpty, reason: 'it stops');
          h.dispose();
        });
      },
    );
  });

  group('5.4 close', () {
    test(
      '5.4 close aborts the stream, ends listeners and leaves no timers or requests',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          final UpdateLog log = h.listen();
          final RealtimeConnection connection = h.server.last;
          h.elapseTo(s(10));
          unawaited(h.remoteConfig.close());
          async.flushMicrotasks();
          expect(connection.aborted, isTrue);
          expect(log.done, isTrue);
          expect(
            async.pendingTimers,
            isEmpty,
            reason: async.pendingTimersDebugString.join('\n'),
          );

          h.elapseTo(const Duration(hours: 25));
          expect(h.server.connections, hasLength(1));
          expect(h.server.fetches, isEmpty);

          final UpdateLog later = h.listen();
          expect(later.done, isTrue);
          expect(h.server.connections, hasLength(1));
          h.dispose();
        });
      },
    );

    test('5.4 close during a backoff cancels the reconnect', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.server.realtimeAnswer = drop;
        h.listen();
        expect(async.pendingTimers, isNotEmpty);
        unawaited(h.remoteConfig.close());
        async.flushMicrotasks();
        expect(
          async.pendingTimers,
          isEmpty,
          reason: async.pendingTimersDebugString.join('\n'),
        );
        h.elapseTo(const Duration(hours: 25));
        expect(h.server.connections, hasLength(1));
        expect(h.installations.callTimes, hasLength(1));
        h.dispose();
      });
    });

    test(
      '5.4 close during the auto-fetch wait sends no fetch and reports nothing',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          final UpdateLog log = h.listen();
          h.server.last.send('{"latestTemplateVersionNumber": "1"}');
          h.elapseTo(s(0.5));
          unawaited(h.remoteConfig.close());
          h.elapseTo(const Duration(hours: 1));
          expect(h.server.fetches, isEmpty);
          expect(log.errors, isEmpty);
          expect(log.done, isTrue);
          h.dispose();
        });
      },
    );

    test('5.4 close during the auto-fetch wait leaves no timer', () {
      fakeAsync((FakeAsync async) {
        final RcHarness h = RcHarness(async);
        h.listen();
        h.server.last.send('{"latestTemplateVersionNumber": "1"}');
        h.elapseTo(s(0.5));
        unawaited(h.remoteConfig.close());
        async.flushMicrotasks();
        // SPEC: 11.7 realtime row "no timers or requests after close"; code leaves the
        // Future<void>.delayed of the auto-fetch wait (up to 3 s, lib/src/realtime/auto_fetch.dart
        // _chain) pending after close.
        expect(
          async.pendingTimers,
          isEmpty,
          reason: async.pendingTimersDebugString.join('\n'),
        );
        h.dispose();
      });
    });
  });

  group('5.9.4 updatedKeys', () {
    TemplateRecord record({
      Map<String, String> entries = const <String, String>{'a': '1'},
      List<Map<String, Object?>> experiments = const <Map<String, Object?>>[],
      List<Map<String, Object?>> rollouts = const <Map<String, Object?>>[],
      Map<String, Map<String, Object?>> personalization =
          const <String, Map<String, Object?>>{},
    }) {
      return TemplateRecord(
        entries: entries,
        fetchTime: rcEpoch,
        experimentDescriptions: experiments,
        rolloutMetadata: rollouts,
        personalizationMetadata: personalization,
      );
    }

    Map<String, Object?> experiment(
      String id, {
      String variant = 'v1',
      String ttl = '1000',
      String trigger = '2000',
      String start = '2026-01-01T00:00:00Z',
      List<String>? keys = const <String>['a'],
    }) {
      return <String, Object?>{
        'experimentId': id,
        'variantId': variant,
        'timeToLiveMillis': ttl,
        'triggerTimeoutMillis': trigger,
        'experimentStartTime': start,
        'affectedParameterKeys': ?keys,
      };
    }

    Map<String, Object?> rollout(String id, String variant, List<String> keys) {
      return <String, Object?>{
        'rolloutId': id,
        'variantId': variant,
        'affectedParameterKeys': keys,
      };
    }

    test(
      '5.9.4 values: added, removed, changed; missing records count as empty',
      () {
        expect(updatedKeys(null, null), isEmpty);
        expect(
          updatedKeys(
            null,
            record(entries: const <String, String>{'a': '1', 'b': '2'}),
          ),
          <String>{'a', 'b'},
        );
        expect(
          updatedKeys(record(entries: const <String, String>{'a': '1'}), null),
          <String>{'a'},
        );
        expect(
          updatedKeys(
            record(
              entries: const <String, String>{'a': '1', 'b': '2', 'c': '3'},
            ),
            record(
              entries: const <String, String>{'a': '1', 'b': '9', 'd': '4'},
            ),
          ),
          <String>{'b', 'c', 'd'},
        );
        expect(updatedKeys(record(), record()), isEmpty);
      },
    );

    test('5.9.4 personalization: in only one, or different', () {
      final Map<String, Object?> p1 = <String, Object?>{
        'personalizationId': 'p1',
        'armIndex': 0,
      };
      final Map<String, Object?> p2 = <String, Object?>{
        'personalizationId': 'p2',
        'armIndex': 0,
      };
      expect(
        updatedKeys(
          record(),
          record(personalization: <String, Map<String, Object?>>{'a': p1}),
        ),
        <String>{'a'},
      );
      expect(
        updatedKeys(
          record(personalization: <String, Map<String, Object?>>{'a': p1}),
          record(personalization: <String, Map<String, Object?>>{'a': p2}),
        ),
        <String>{'a'},
      );
    });

    test('5.9.4 rollouts: a changed variant or a new rollout on the key', () {
      final Map<String, String> entries = <String, String>{'a': '1', 'b': '1'};
      expect(
        updatedKeys(
          record(
            entries: entries,
            rollouts: <Map<String, Object?>>[
              rollout('r1', 'v1', <String>['a']),
            ],
          ),
          record(
            entries: entries,
            rollouts: <Map<String, Object?>>[
              rollout('r1', 'v2', <String>['a']),
            ],
          ),
        ),
        <String>{'a'},
      );
      expect(
        updatedKeys(
          record(
            entries: entries,
            rollouts: <Map<String, Object?>>[
              rollout('r1', 'v1', <String>['a']),
            ],
          ),
          record(
            entries: entries,
            rollouts: <Map<String, Object?>>[
              rollout('r1', 'v1', <String>['a', 'b']),
            ],
          ),
        ),
        <String>{'b'},
      );
    });

    test(
      '5.9.4 experiments: experimentId, variantId, timeToLiveMillis, triggerTimeoutMillis',
      () {
        final TemplateRecord base = record(
          experiments: <Map<String, Object?>>[experiment('e1')],
        );
        for (final Map<String, Object?> changed in <Map<String, Object?>>[
          experiment('e2'),
          experiment('e1', variant: 'v2'),
          experiment('e1', ttl: '1001'),
          experiment('e1', trigger: '2001'),
        ]) {
          expect(
            updatedKeys(
              base,
              record(experiments: <Map<String, Object?>>[changed]),
            ),
            <String>{'a'},
            reason: '$changed',
          );
        }
        expect(
          updatedKeys(
            base,
            record(
              experiments: <Map<String, Object?>>[
                experiment('e1', start: '2027-01-01T00:00:00Z'),
              ],
            ),
          ),
          isEmpty,
          reason: 'experimentStartTime is not compared',
        );
      },
    );

    test(
      '5.9.4 experiments without affectedParameterKeys or with an _exp_rollout id are skipped',
      () {
        expect(
          updatedKeys(
            record(
              experiments: <Map<String, Object?>>[experiment('e1', keys: null)],
            ),
            record(
              experiments: <Map<String, Object?>>[
                experiment('e1', variant: 'v2', keys: null),
              ],
            ),
          ),
          isEmpty,
        );
        expect(
          updatedKeys(
            record(
              experiments: <Map<String, Object?>>[experiment('_exp_rollout_7')],
            ),
            record(
              experiments: <Map<String, Object?>>[
                experiment('_exp_rollout_7', variant: 'v2'),
              ],
            ),
          ),
          isEmpty,
        );
        expect(
          updatedKeys(
            record(),
            record(
              experiments: <Map<String, Object?>>[experiment('_exp_rollout_8')],
            ),
          ),
          isEmpty,
        );
      },
    );

    test('5.9.4 key order never matters', () {
      expect(
        updatedKeys(
          record(
            entries: const <String, String>{'a': '1', 'b': '2'},
            personalization: <String, Map<String, Object?>>{
              'a': <String, Object?>{'personalizationId': 'p1', 'armIndex': 0},
            },
            rollouts: <Map<String, Object?>>[
              rollout('r1', 'v1', <String>['a', 'b']),
              rollout('r2', 'v1', <String>['b']),
            ],
            experiments: <Map<String, Object?>>[
              experiment('e1', keys: <String>['a', 'b']),
              experiment('e2', keys: <String>['b']),
            ],
          ),
          record(
            entries: const <String, String>{'b': '2', 'a': '1'},
            personalization: <String, Map<String, Object?>>{
              'a': <String, Object?>{'armIndex': 0, 'personalizationId': 'p1'},
            },
            rollouts: <Map<String, Object?>>[
              rollout('r2', 'v1', <String>['b']),
              rollout('r1', 'v1', <String>['b', 'a']),
            ],
            experiments: <Map<String, Object?>>[
              experiment('e2', keys: <String>['b']),
              experiment('e1', keys: <String>['b', 'a']),
            ],
          ),
        ),
        isEmpty,
      );
    });
  });
}
