// Spec v4 5.11 rule 6 for Installations: no log line, exception message or toString holds the refresh
// token, the auth token or the API key, over every failure path. Each sentinel contains the word
// SENTINEL, so a partial copy is caught too. Remote Config's sentinels (custom signals, realtime
// statuses, invalid messages, signal limits) are covered by its own leakage test.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:firebase_installations_dart/src/record.dart';
import 'package:firebase_installations_dart/src/rest_client.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/fis_sec_io.dart';
import '../support/fis_sec_support.dart';

const String _marker = 'SENTINEL';

void _expectClean(Iterable<String> texts, String scenario) {
  for (final String text in texts) {
    expect(text, isNot(contains(_marker)), reason: scenario);
  }
}

/// A store over a [MemoryKeyValueStore] whose writes fail once [failWrites] is set, with an exception
/// whose text holds the value it was given (a careless store implementation).
final class _LeakyFailingStore implements KeyValueStore {
  final MemoryKeyValueStore _inner = MemoryKeyValueStore();
  bool failReads = false;
  bool failWrites = false;

  @override
  Future<String?> read(String key) {
    if (failReads) {
      throw _StoreFailure('read of $key failed near $fisSecRefreshToken');
    }
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String? value) {
    if (failWrites) {
      throw _StoreFailure('write of $key failed: $value');
    }
    return _inner.write(key, value);
  }

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) async {
    if (failWrites) {
      final String? current = await _inner.read(key);
      throw _StoreFailure('update of $key failed: ${transform(current)}');
    }
    return _inner.update(key, transform);
  }

  @override
  Stream<String> get changes => const Stream<String>.empty();

  @override
  Future<void> close() => _inner.close();
}

final class _StoreFailure implements Exception {
  _StoreFailure(this.message);

  final String message;

  @override
  String toString() => '_StoreFailure: $message';
}

/// One instance with a log, a store and a fake server, and the texts its failures produced.
final class _Probe {
  _Probe(FisSecHandler handler, {KeyValueStore? store})
    : client = FisSecClient(handler) {
    this.store = store ?? MemoryKeyValueStore();
    app = fisSecApp();
    installations = fisSecInstallations(
      app,
      store: this.store,
      client: client,
      logger: log.call,
    );
  }

  final FisSecClient client;
  final FisSecLog log = FisSecLog();
  late final KeyValueStore store;
  late final FirebaseApp app;
  late final FirebaseInstallations installations;
  final List<String> texts = <String>[];

  /// Seeds a registered record whose token expired (so getToken sends generate).
  Future<void> seedExpired() => store.write(
    fisSecRecordKey(app),
    fisSecRegisteredRecord(
      tokenCreatedAt: fisSecNow.subtract(const Duration(days: 30)),
    ),
  );

  /// Runs [action] and keeps the text of its error, if any.
  Future<Object?> run(Future<Object?> Function() action) async {
    final Object? error = await fisSecErrorOf(action);
    texts.add(fisSecErrorText(error));
    return error;
  }

  /// Every text a caller or a log reader sees.
  Iterable<String> get all => <String>[
    ...texts,
    ...log.lines,
    installations.toString(),
  ];
}

void main() {
  test(
    '5.11 rule 6: the sentinels hold the marker and the API key passes the constructor check',
    () {
      for (final String sentinel in <String>[
        fisSecApiKey,
        fisSecRefreshToken,
        fisSecAuthToken,
      ]) {
        expect(sentinel, contains(_marker));
      }
      expect(RegExp(r'^A[A-Za-z0-9_-]{38}$').hasMatch(fisSecApiKey), isTrue);
    },
  );

  const List<int> statuses = <int>[400, 401, 403, 404, 409, 429, 500, 503];

  group('5.11 rule 6 each status class', () {
    for (final int status in statuses) {
      test('5.11 rule 6: create answered $status leaks nothing', () async {
        int creates = 0;
        final _Probe probe = _Probe((FisSecRequest r) {
          if (r.route != 'create') {
            return fisSecHappyHandler()(r);
          }
          creates++;
          // One 409 shows the conflict path (A4: the call restarts with a new FID); the later creates
          // succeed so the success path is covered too.
          if (status == 409 && creates > 1) {
            return fisSecCreateOk();
          }
          return fisSecError(
            status,
            serverStatus: 'STATUS_$status',
            message: 'Request failed with $status.',
          );
        });
        await probe.run(probe.installations.getId);
        await probe.run(probe.installations.getToken);
        await probe.run(probe.installations.getToken);
        await pumpEventQueue();
        _expectClean(probe.all, 'create $status');
      });

      test('5.11 rule 6: generate answered $status leaks nothing', () async {
        final _Probe probe = _Probe(
          (FisSecRequest r) => r.route == 'generate'
              ? fisSecError(
                  status,
                  serverStatus: 'STATUS_$status',
                  message: 'Request failed with $status.',
                )
              : fisSecHappyHandler()(r),
        );
        await probe.seedExpired();
        await probe.run(probe.installations.getToken);
        await probe.run(() => probe.installations.getToken(forceRefresh: true));
        await probe.run(probe.installations.getIdAndToken);
        _expectClean(probe.all, 'generate $status');
      });

      test('5.11 rule 6: delete answered $status leaks nothing', () async {
        final _Probe probe = _Probe(
          (FisSecRequest r) => r.route == 'delete'
              ? fisSecError(
                  status,
                  serverStatus: 'STATUS_$status',
                  message: 'Request failed with $status.',
                )
              : fisSecHappyHandler()(r),
        );
        await probe.seedExpired();
        await probe.run(probe.installations.delete);
        _expectClean(probe.all, 'delete $status');
      });
    }
  });

  group('5.11 rule 6 malformed answers', () {
    for (final int status in <int>[200, 400, 500]) {
      test('5.11 rule 6: a non-JSON $status body leaks nothing', () async {
        final _Probe probe = _Probe(
          (FisSecRequest r) =>
              fisSecText(status, '<html><body>Error</body></html>'),
        );
        await probe.run(probe.installations.getToken);
        _expectClean(probe.all, 'non-JSON $status');
      });
    }

    test(
      '5.11 rule 6: a 2xx create body holding the refresh token but no auth token leaks nothing',
      () async {
        final _Probe probe = _Probe(
          (FisSecRequest r) => fisSecJson(200, <String, Object?>{
            'refreshToken': fisSecRefreshToken,
            'authToken': 'x',
          }),
        );
        final Object? error = await probe.run(probe.installations.getToken);
        expect(error, isFisCode('invalid-response'));
        _expectClean(probe.all, 'invalid create body');
      },
    );

    test(
      '5.11 rule 6: a 2xx generate body with a bad expiresIn leaks nothing',
      () async {
        final _Probe probe = _Probe(
          (FisSecRequest r) => r.route == 'generate'
              ? fisSecGenerateOk(expiresIn: 'forever')
              : fisSecHappyHandler()(r),
        );
        await probe.seedExpired();
        final Object? error = await probe.run(probe.installations.getToken);
        expect(error, isFisCode('invalid-response'));
        _expectClean(probe.all, 'invalid generate body');
      },
    );

    test('5.11 rule 6: an endless 2xx body leaks nothing', () async {
      final FisSecEndless body = FisSecEndless();
      final _Probe probe = _Probe((FisSecRequest r) => body.response(200));
      await probe.run(probe.installations.getToken);
      _expectClean(probe.all, 'endless body');
    });
  });

  group('5.11 rule 6 transport', () {
    test(
      '5.11 rule 6: a 3xx with the API key in its Location leaks nothing',
      () async {
        final _Probe probe = _Probe(
          (FisSecRequest r) => fisSecText(
            302,
            '',
            headers: <String, String>{
              'location':
                  'https://evil.example/?key=$fisSecApiKey&rt=$fisSecRefreshToken',
            },
          ),
        );
        final Object? error = await probe.run(probe.installations.getToken);
        expect(error, isFisCode('invalid-response'));
        _expectClean(probe.all, '3xx');
      },
    );

    test(
      '5.11 rule 6: a transport exception whose text and uri hold secrets leaks nothing',
      () async {
        final _Probe probe = _Probe((FisSecRequest r) {
          throw http.ClientException(
            'failed with Authorization: FIS_v2 $fisSecRefreshToken',
            Uri.parse('https://fis.test.example/v1?key=$fisSecApiKey'),
          );
        });
        await probe.seedExpired();
        final Object? error = await probe.run(probe.installations.getToken);
        expect(error, isFisCode('network-error'));
        expect(
          (error! as FirebaseInstallationsException).cause,
          isA<http.ClientException>(),
        );
        await probe.run(probe.installations.delete);
        _expectClean(probe.all, 'transport');
      },
    );

    test(
      '5.11 rule 6: a SocketException in the background registration leaks nothing to the log',
      () async {
        final _Probe probe = _Probe((FisSecRequest r) {
          throw SocketException(
            'refused $fisSecApiKey',
            address: InternetAddress.loopbackIPv4,
          );
        });
        await probe.run(probe.installations.getId);
        await pumpEventQueue();
        expect(
          probe.log.lines,
          isNotEmpty,
          reason: 'the background failure is logged',
        );
        _expectClean(probe.all, 'socket');
      },
    );

    test('5.11 rule 6: the 10 s request timeout leaks nothing', () {
      fakeAsync((FakeAsync async) {
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => Completer<http.StreamedResponse>().future,
        );
        final FisSecLog log = FisSecLog();
        final FirebaseInstallations installations = FirebaseInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          httpClient: client,
          logger: log.call,
          serverOrigin: fisSecOrigin,
          clock: () => fisSecNow,
          random: () => 0.5,
          randomBytes: fisSecZeroBytes,
          delay: Future<void>.delayed,
        );
        Object? error;
        unawaited(
          installations.getToken().then<void>(
            (_) {},
            onError: (Object e) => error = e,
          ),
        );
        async.elapse(const Duration(seconds: 30));
        expect(error, isFisCode('network-error'));
        expect(client.requests, hasLength(2));
        _expectClean(<String>[fisSecErrorText(error), ...log.lines], 'timeout');
        unawaited(installations.close());
        async.flushMicrotasks();
      });
    });
  });

  group('5.11 rule 6 store failures', () {
    test(
      '5.11 rule 6: a write failure after start, with the record in the exception text, leaks nothing',
      () async {
        final _LeakyFailingStore store = _LeakyFailingStore();
        final _Probe probe = _Probe(fisSecHappyHandler(), store: store);
        expect(await probe.installations.getId(), fisSecFid);
        store.failWrites = true;
        await probe.run(probe.installations.getToken);
        await probe.run(() => probe.installations.getToken(forceRefresh: true));
        await probe.run(probe.installations.delete);
        expect(
          probe.log.lines.where((String l) => l.contains('kept in memory')),
          isNotEmpty,
        );
        _expectClean(probe.all, 'write failure');
      },
    );

    test(
      '5.11 rule 6: a store failing at first use, with secrets in its exception, gives a clean storage-error',
      () async {
        final _LeakyFailingStore store = _LeakyFailingStore()..failReads = true;
        final _Probe probe = _Probe(fisSecHappyHandler(), store: store);
        final Object? error = await probe.run(probe.installations.getId);
        expect(error, isFisCode('storage-error'));
        _expectClean(probe.all, 'configuration failure');
      },
    );

    test(
      '5.11 rule 6: a corrupt record holding the sentinels is reported without them',
      () async {
        final _Probe probe = _Probe(fisSecHappyHandler());
        await probe.store.write(
          fisSecRecordKey(probe.app),
          '${fisSecRegisteredRecord()}{',
        );
        await probe.run(probe.installations.getToken);
        expect(
          probe.log.lines.where((String l) => l.contains('could not be read')),
          hasLength(1),
        );
        _expectClean(probe.all, 'corrupt record');
      },
    );
  });

  group('5.11 rule 6 logs of a full run', () {
    test(
      '5.11 rule 6: create, generate, forced generate and delete log no secret (memory store)',
      () async {
        final _Probe probe = _Probe(fisSecHappyHandler());
        await probe.run(probe.installations.getId);
        await probe.run(probe.installations.getToken);
        await probe.run(() => probe.installations.getToken(forceRefresh: true));
        await probe.run(probe.installations.delete);
        expect(probe.log.lines, isNotEmpty);
        _expectClean(probe.all, 'full run');
      },
    );

    test('5.11 rule 6: the file store and its logger log no secret', () async {
      final Directory dir = fisSecTempDir();
      final FisSecLog storeLog = FisSecLog();
      final FileKeyValueStore store = FileKeyValueStore(
        dir.path,
        logger: storeLog.call,
      );
      addTearDown(store.close);
      final _Probe probe = _Probe(fisSecHappyHandler(), store: store);
      await probe.run(probe.installations.getToken);
      await probe.run(() => probe.installations.getToken(forceRefresh: true));
      await probe.run(probe.installations.delete);
      _expectClean(<String>[
        ...probe.all,
        ...storeLog.lines,
        store.toString(),
      ], 'file store');
    });
  });

  group('5.11 rule 6 toString of records and results', () {
    test('5.11 rule 6: InstallationRecord prints <redacted>', () {
      final InstallationRecord record = InstallationRecord.tryParse(
        fisSecRegisteredRecord(),
      )!;
      expect(record.toString(), contains('<redacted>'));
      _expectClean(<String>[record.toString()], 'record');
    });

    test(
      '5.11 rule 6: RegisteredInstallation and AuthTokenResult print <redacted>',
      () {
        final AuthTokenResult token = AuthTokenResult(
          token: fisSecAuthToken,
          expiresIn: const Duration(days: 7),
          createdAt: fisSecNow,
        );
        final RegisteredInstallation registered = RegisteredInstallation(
          fid: fisSecFid,
          refreshToken: fisSecRefreshToken,
          token: token,
        );
        for (final Object value in <Object>[token, registered]) {
          expect(value.toString(), contains('<redacted>'));
        }
        _expectClean(<String>[
          token.toString(),
          registered.toString(),
        ], 'results');
      },
    );

    test(
      '5.11 rule 6 / 5.3: a malformed API key is not echoed by invalid-app-config',
      () {
        const String badKey = 'not-a-key-SENTINEL';
        Object? error;
        try {
          FirebaseInstallations(
            fisSecApp(apiKey: badKey),
            store: MemoryKeyValueStore(),
            httpClient: FisSecClient(fisSecHappyHandler()),
          );
        } on Object catch (e) {
          error = e;
        }
        expect(error, isFisCode('invalid-app-config'));
        _expectClean(<String>[fisSecErrorText(error)], 'invalid-app-config');
      },
    );
  });

  group('5.11 rule 6 server text only in serverMessage', () {
    test('5.11 rule 6: server text is not part of message or toString', () async {
      // 5.11 rule 6 ("server text reaches callers only as serverMessage"); A6: toString prints the
      // code, message and HTTP status only.
      final _Probe probe = _Probe(
        (FisSecRequest r) => fisSecError(400, message: 'server-said-this'),
      );
      final Object? error = await probe.run(probe.installations.getToken);
      final FirebaseInstallationsException exception =
          error! as FirebaseInstallationsException;
      expect(exception.serverMessage, 'server-said-this');
      expect(exception.message, isNot(contains('server-said-this')));
      expect(exception.toString(), isNot(contains('server-said-this')));
    });

    test(
      '5.11 rule 6: a server echoing the API key and refresh token does not put them in toString',
      () async {
        // 5.11 rule 6 and A6: toString never includes serverMessage (which may echo request secrets).
        final _Probe probe = _Probe(
          (FisSecRequest r) => r.route == 'generate'
              ? fisSecError(
                  401,
                  message:
                      'Refresh token $fisSecRefreshToken for key $fisSecApiKey is revoked.',
                )
              : fisSecError(400, message: 'API key not valid: $fisSecApiKey'),
        );
        final Object? error = await probe.run(probe.installations.getToken);
        final FirebaseInstallationsException exception =
            error! as FirebaseInstallationsException;
        expect(exception.message, isNot(contains(_marker)));
        expect(exception.toString(), isNot(contains(_marker)));
        expect(probe.log.lines.join('\n'), isNot(contains(_marker)));
      },
    );
  });
}
