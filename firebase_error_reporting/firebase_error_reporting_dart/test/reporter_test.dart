import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';
import 'package:test/test.dart';

import 'fakes.dart';

class _NoJitter implements Random {
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}

/// A store that records saves and can fail.
class _Store implements ErrorReportingStore {
  _Store([this.state = ErrorReportingState.empty]);

  ErrorReportingState state;
  Object? loadError;
  Object? saveError;
  int saves = 0;

  @override
  Future<ErrorReportingState> load() async {
    final Object? error = loadError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return state;
  }

  @override
  Future<void> save(ErrorReportingState state) async {
    saves++;
    final Object? error = saveError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    this.state = state;
  }
}

final DateTime _start = DateTime.utc(2026, 11, 28, 12);

/// A stack whose top frame is at [line], so errors of one type can differ in kind.
StackTrace _stackAt(int line) =>
    StackTrace.fromString('#0      f (package:notes/f.dart:$line:1)\n');

class _Harness {
  _Harness(
    this.async, {
    List<int> statuses = const <int>[200],
    ErrorReportingStore? store,
    FirebaseApp? app,
    BeforeSend? beforeSend,
    bool enabledByDefault = true,
    int maxQueueLength = 100,
    ErrorReportingTransport? transport,
  }) : server = Server(statuses) {
    reporter = ErrorReporter(
      app ?? newApp(),
      service: 'notes',
      version: '1.0.0',
      transport:
          transport ?? ErrorReportingTransport.direct(apiKey: 'AIzaSecretKey'),
      store: store,
      beforeSend: beforeSend,
      collectionEnabledByDefault: enabledByDefault,
      maxQueueLength: maxQueueLength,
      httpClient: server.client,
      clock: () => _start.add(async.elapsed),
      random: _NoJitter(),
      onDiagnostic: logs.add,
    );
  }

  final FakeAsync async;
  final Server server;
  final List<String> logs = <String>[];
  late final ErrorReporter reporter;

  void record(Object error, [StackTrace? stack, bool fatal = false]) {
    reporter.recordError(error, stack ?? appStack, fatal: fatal);
    async.flushMicrotasks();
  }
}

void main() {
  test('an error is sent after the send delay, as a ReportedErrorEvent', () {
    fakeAsync((FakeAsync async) {
      final _Harness h = _Harness(async);
      h.record(StateError('no element'));
      async.elapse(const Duration(milliseconds: 1999));
      expect(h.server.requests, isEmpty);
      expect(h.reporter.pendingCount, 1);
      async.elapse(const Duration(milliseconds: 1));
      final Received sent = h.server.requests.single;
      expect(sent.body['serviceContext'], <String, Object?>{
        'service': 'notes',
        'version': '1.0.0',
      });
      expect(sent.body['eventTime'], _start.toIso8601String());
      expect(
        sent.message,
        startsWith('StateError: Bad state: no element\n    at ListBase.first'),
      );
      expect(
        (sent.body['context']! as Map<String, Object?>)['reportLocation'],
        <String, Object?>{
          'filePath': 'package:notes/src/repository.dart',
          'lineNumber': 42,
          'functionName': 'NoteRepository.load',
        },
      );
      expect(h.reporter.pendingCount, 0);
    });
  });

  test('errors recorded within the delay go out together, in order', () {
    fakeAsync((FakeAsync async) {
      final _Harness h = _Harness(async);
      h.record(StateError('one'), _stackAt(1));
      async.elapse(const Duration(seconds: 1));
      h.record(StateError('two'), _stackAt(2));
      async.elapse(const Duration(seconds: 1));
      expect(
        h.server.requests.map((Received r) => r.message.split('\n').first),
        <String>['StateError: Bad state: one', 'StateError: Bad state: two'],
      );
    });
  });

  test('a fatal error is sent at once, with [fatal] in the header', () {
    fakeAsync((FakeAsync async) {
      final _Harness h = _Harness(async);
      h.record(StateError('down'), appStack, true);
      async.elapse(Duration.zero);
      expect(
        h.server.requests.single.message,
        startsWith('StateError: [fatal] Bad state: down'),
      );
    });
  });

  test('a failed send is retried with backoff until it is delivered', () {
    fakeAsync((FakeAsync async) {
      final _Harness h = _Harness(async, statuses: <int>[503, 503, 200]);
      h.record(StateError('x'));
      async.elapse(const Duration(seconds: 2));
      expect(h.server.requests, hasLength(1));
      // No jitter: half of 2 s, then half of 4 s.
      async.elapse(const Duration(milliseconds: 999));
      expect(h.server.requests, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      expect(h.server.requests, hasLength(2));
      async.elapse(const Duration(seconds: 2));
      expect(h.server.requests, hasLength(3));
      expect(h.reporter.pendingCount, 0);
      expect(h.logs.where((String l) => l.contains('HTTP 503')), hasLength(2));
    });
  });

  test('Retry-After decides the wait', () {
    fakeAsync((FakeAsync async) {
      final _Harness h = _Harness(async, statuses: <int>[429, 200]);
      h.server.responseHeaders = <String, String>{'retry-after': '30'};
      h.record(StateError('x'));
      async.elapse(const Duration(seconds: 2));
      async.elapse(const Duration(seconds: 29));
      expect(h.server.requests, hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(h.server.requests, hasLength(2));
    });
  });

  test('an event the server refuses is dropped and the next one is sent', () {
    fakeAsync((FakeAsync async) {
      final _Harness h = _Harness(async, statuses: <int>[400, 200]);
      h.server.responseBody = '{"error":{"message":"bad eventTime"}}';
      h.record(StateError('one'), _stackAt(1));
      h.record(StateError('two'), _stackAt(2));
      async.elapse(const Duration(seconds: 2));
      expect(h.server.requests, hasLength(2));
      expect(h.reporter.pendingCount, 0);
      expect(h.logs.single, contains('HTTP 400'));
      expect(h.logs.single, contains('bad eventTime'));
    });
  });

  group('rate limit', () {
    test(
      'at most 5 a minute of one kind; the next says how many were dropped',
      () {
        fakeAsync((FakeAsync async) {
          final _Harness h = _Harness(async, statuses: <int>[500]);
          for (int i = 0; i < 8; i++) {
            h.record(StateError('loop'));
          }
          expect(h.reporter.pendingCount, 5);
          async.elapse(const Duration(minutes: 1));
          h.record(StateError('loop'));
          expect(h.reporter.pendingCount, 6);
          h.reporter.flush();
          async.flushMicrotasks();
          expect(h.server.requests.last.message, isNot(contains('dropped')));
        });
      },
    );

    test('the note goes into the header of the next admitted event', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(async);
        for (int i = 0; i < 8; i++) {
          h.record(StateError('loop'));
        }
        async.elapse(const Duration(minutes: 1));
        h.record(StateError('loop'));
        async.elapse(const Duration(seconds: 2));
        expect(h.server.requests, hasLength(6));
        expect(
          h.server.requests.last.message.split('\n').first,
          'StateError: Bad state: loop [+3 similar dropped]',
        );
      });
    });

    test('at most 30 a minute in all', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(async, statuses: <int>[500]);
        for (int i = 0; i < 40; i++) {
          h.record(StateError('e$i'), _stackAt(i + 1));
        }
        expect(h.reporter.pendingCount, 30);
      });
    });
  });

  test('the queue keeps the newest events when full', () {
    fakeAsync((FakeAsync async) {
      final _Store store = _Store();
      final _Harness h = _Harness(
        async,
        statuses: <int>[500],
        store: store,
        maxQueueLength: 3,
      );
      for (int i = 0; i < 5; i++) {
        h.record(StateError('e$i'), _stackAt(i + 1));
      }
      expect(
        store.state.queue.map((ErrorEvent e) => e.message.split('\n').first),
        <String>[
          'StateError: Bad state: e2',
          'StateError: Bad state: e3',
          'StateError: Bad state: e4',
        ],
      );
      expect(h.logs, contains(contains('dropped the 1 oldest')));
    });
  });

  test(
    'the queue of an earlier run is sent at start; events older than 30 days are dropped',
    () {
      fakeAsync((FakeAsync async) {
        ErrorEvent event(Duration age, String text) => ErrorEvent(
          eventTime: _start.subtract(age),
          message: text,
          fingerprint: text,
        );
        final _Store store = _Store(
          ErrorReportingState(
            queue: <ErrorEvent>[
              event(const Duration(days: 31), 'old'),
              event(const Duration(days: 29), 'recent'),
            ],
          ),
        );
        final _Harness h = _Harness(async, store: store);
        async.elapse(Duration.zero);
        expect(h.server.requests.map((Received r) => r.message), <String>[
          'recent',
        ]);
        expect(store.state.queue, isEmpty);
      });
    },
  );

  group('collection', () {
    test('turning it off drops the queue, is saved, and stops recording', () {
      fakeAsync((FakeAsync async) {
        final _Store store = _Store();
        final _Harness h = _Harness(async, statuses: <int>[500], store: store);
        h.record(StateError('a'));
        h.reporter.setCollectionEnabled(false);
        async.flushMicrotasks();
        expect(h.reporter.isCollectionEnabled, isFalse);
        expect(store.state.queue, isEmpty);
        expect(store.state.collectionEnabled, isFalse);
        h.record(StateError('b'));
        async.elapse(const Duration(minutes: 5));
        expect(h.reporter.pendingCount, 0);

        final _Harness next = _Harness(async, store: store);
        async.flushMicrotasks();
        expect(next.reporter.isCollectionEnabled, isFalse);
      });
    });

    test('off by default records nothing until it is turned on', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(async, enabledByDefault: false);
        h.record(StateError('a'));
        expect(h.reporter.pendingCount, 0);
        h.reporter.setCollectionEnabled(true);
        async.flushMicrotasks();
        h.record(StateError('b'));
        async.elapse(const Duration(seconds: 2));
        expect(h.server.requests.single.message, contains('Bad state: b'));
      });
    });
  });

  test('setUser applies to later events and is saved', () {
    fakeAsync((FakeAsync async) {
      final _Store store = _Store();
      final _Harness h = _Harness(async, store: store);
      h.record(StateError('before'), _stackAt(1));
      h.reporter.setUser('user-7');
      async.flushMicrotasks();
      h.record(StateError('after'), _stackAt(2));
      async.elapse(const Duration(seconds: 2));
      final List<Map<String, Object?>> contexts = <Map<String, Object?>>[
        for (final Received r in h.server.requests)
          r.body['context']! as Map<String, Object?>,
      ];
      expect(contexts[0].containsKey('user'), isFalse);
      expect(contexts[1]['user'], 'user-7');
      expect(store.state.user, 'user-7');
    });
  });

  group('beforeSend', () {
    test('can scrub an event', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(
          async,
          beforeSend: (ErrorEvent e) => e.copyWith(
            message: e.message.replaceAll('secret@example.com', '<email>'),
          ),
        );
        h.record(StateError('user secret@example.com'));
        async.elapse(const Duration(seconds: 2));
        expect(h.server.requests.single.message, contains('user <email>'));
      });
    });

    test(
      'null drops the event; a throw drops it and is logged, not reported',
      () {
        fakeAsync((FakeAsync async) {
          int calls = 0;
          final _Harness h = _Harness(
            async,
            beforeSend: (ErrorEvent e) {
              calls++;
              if (calls == 1) {
                return null;
              }
              throw StateError('hook broke');
            },
          );
          h.record(StateError('a'), _stackAt(1));
          h.record(StateError('b'), _stackAt(2));
          async.elapse(const Duration(minutes: 1));
          expect(h.server.requests, isEmpty);
          expect(calls, 2);
          expect(h.logs.single, contains('beforeSend threw StateError'));
        });
      },
    );
  });

  group('store failures', () {
    test('a store that cannot be read starts empty', () {
      fakeAsync((FakeAsync async) {
        final _Store store = _Store()
          ..loadError = const FormatException('corrupt');
        final _Harness h = _Harness(async, store: store);
        h.record(StateError('a'));
        async.elapse(const Duration(seconds: 2));
        expect(h.server.requests, hasLength(1));
        expect(h.logs.first, contains('could not be read (FormatException)'));
      });
    });

    test('a store that cannot be written does not stop sending', () {
      fakeAsync((FakeAsync async) {
        final _Store store = _Store()..saveError = StateError('disk full');
        final _Harness h = _Harness(async, store: store);
        h.record(StateError('a'));
        async.elapse(const Duration(seconds: 2));
        expect(h.server.requests, hasLength(1));
        expect(h.logs, contains(contains('could not be saved (StateError)')));
      });
    });
  });

  test('close sends the queue, and later errors are not recorded', () {
    fakeAsync((FakeAsync async) {
      final _Harness h = _Harness(async);
      h.record(StateError('a'));
      bool closed = false;
      h.reporter.close().then((_) => closed = true);
      async.flushMicrotasks();
      expect(closed, isTrue);
      expect(h.server.requests, hasLength(1));
      h.record(StateError('b'));
      async.elapse(const Duration(minutes: 1));
      expect(h.server.requests, hasLength(1));
      expect(h.logs.last, contains('after close'));
    });
  });

  test('close with a failing server keeps the queue in the store', () {
    fakeAsync((FakeAsync async) {
      final _Store store = _Store();
      final _Harness h = _Harness(async, statuses: <int>[503], store: store);
      h.record(StateError('a'));
      h.reporter.close();
      async.elapse(const Duration(seconds: 11));
      expect(store.state.queue, hasLength(1));
    });
  });

  group('runGuarded', () {
    test('records a failure of the body and completes with null', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(async);
        Object? result = 'pending';
        h.reporter
            .runGuarded<int>(() async {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              throw StateError('body failed');
            })
            .then((int? r) => result = r);
        async.elapse(const Duration(seconds: 3));
        expect(result, isNull);
        expect(h.server.requests.single.message, contains('body failed'));
      });
    });

    test(
      'records an error nobody waits for and returns the body\'s result',
      () {
        fakeAsync((FakeAsync async) {
          final _Harness h = _Harness(async);
          int? result;
          h.reporter
              .runGuarded<int>(() {
                unawaited(Future<void>(() => throw ArgumentError('stray')));
                return 7;
              })
              .then((int? r) => result = r);
          async.elapse(const Duration(seconds: 3));
          expect(result, 7);
          expect(
            h.server.requests.single.message,
            contains('ArgumentError: Invalid argument(s): stray'),
          );
        });
      },
    );
  });

  test(
    'without a stack, the stack of the call is used, without the reporter\'s frames',
    () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(async);
        h.reporter.recordError(StateError('no stack'), null);
        async.elapse(const Duration(seconds: 2));
        final String message = h.server.requests.single.message;
        expect(
          message.split('\n')[1],
          isNot(contains('package:firebase_error_reporting_dart')),
        );
      });
    },
  );

  test('recordErrorText takes an isolate error\'s strings', () {
    fakeAsync((FakeAsync async) {
      final _Harness h = _Harness(async);
      h.reporter.recordErrorText(
        'Bad state: in isolate',
        appStack.toString(),
        typeName: 'IsolateError',
      );
      async.elapse(const Duration(seconds: 2));
      expect(
        h.server.requests.single.message,
        startsWith(
          'IsolateError: Bad state: in isolate\n    at ListBase.first',
        ),
      );
    });
  });

  test('the direct transport needs the project id of the app', () {
    expect(
      () => ErrorReporter(
        newApp(projectId: null),
        service: 's',
        transport: ErrorReportingTransport.direct(apiKey: 'k'),
      ),
      throwsArgumentError,
    );
    expect(
      () => ErrorReporter(
        newApp(projectId: 'bad/../id'),
        service: 's',
        transport: ErrorReportingTransport.direct(apiKey: 'k'),
      ),
      throwsArgumentError,
    );
    expect(
      () => ErrorReporter(
        newApp(),
        service: ' ',
        transport: ErrorReportingTransport.direct(apiKey: 'k'),
      ),
      throwsArgumentError,
    );
  });

  test('an error whose toString throws is still recorded', () {
    fakeAsync((FakeAsync async) {
      final _Harness h = _Harness(async);
      h.record(_BadToString());
      async.elapse(const Duration(seconds: 2));
      expect(
        h.server.requests.single.message,
        startsWith(
          '_BadToString: Instance of _BadToString (its toString threw)',
        ),
      );
    });
  });
}

class _BadToString {
  @override
  String toString() => throw StateError('no');
}
