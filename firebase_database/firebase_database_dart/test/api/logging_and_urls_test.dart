// What log lines and URL errors may quote: a failed get logs the query's shape, never its bound
// values; data the client cannot read is logged with the error's type only; an
// http database URL names this API's emulator setting; refFromUrl compares the namespace and
// never quotes the URL. Each group names the mutation of lib it was seen failing on
// (rtdb/from_helper/reports/fix_round/logging_and_urls.md).
//
// Every server request here is answered while it is the only one pending.

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show firebaseDatabaseWithConnection;
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

/// A connected database over a [FakeServerActions] whose logger records every message.
final class _Wire {
  _Wire(this.time) {
    db = firebaseDatabaseWithConnection(
      newTestApp(),
      connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) =>
          server..delegate = delegate,
      logger: (DatabaseLogLevel level, String message) =>
          messages.add('${level.name}: $message'),
    );
    time.elapse(Duration.zero);
    server.connect();
    time.elapse(Duration.zero);
  }

  final FakeTime time;
  final FakeServerActions server = FakeServerActions();
  final List<String> messages = <String>[];
  late final FirebaseDatabase db;

  /// Runs [query]'s get, answers its one server request with [status] and [data], and returns
  /// the error the get failed with.
  Object failedGet(Query query, {required String status, Object? data}) {
    final int before = server.callsOf('get').length;
    Object? failure;
    query.get().then<void>(
      (DataSnapshot _) => fail('the get must fail'),
      onError: (Object e) => failure = e,
    );
    time.elapse(Duration.zero);
    final List<ServerCall> gets = server.callsOf('get');
    expect(gets, hasLength(before + 1), reason: 'one get request');
    server.respond(gets.last, status: status, data: data);
    time.elapse(Duration.zero);
    expect(failure, isNotNull);
    return failure!;
  }
}

void main() {
  void timed(String name, void Function(FakeTime time) body) {
    test(name, () => fakeTime(body));
  }

  // Mutation L: in core/repo_get.dart `_onGetError`, log `${request.query}` in place of
  // `${_queryShape(request.query)}`.
  group('a failed get logs the query shape, never its values', () {
    const String secret = 'ada@example.com';

    final Map<String, Query Function(FirebaseDatabase db)> queries =
        <String, Query Function(FirebaseDatabase db)>{
          'equalTo': (FirebaseDatabase db) =>
              db.ref('users').orderByChild('email').equalTo(secret),
          'startAt': (FirebaseDatabase db) =>
              db.ref('users').orderByChild('email').startAt(secret),
          'endAt': (FirebaseDatabase db) =>
              db.ref('users').orderByChild('email').endAt(secret),
          'startAt with a key and a limit': (FirebaseDatabase db) => db
              .ref('users')
              .orderByChild('email')
              .startAt(secret, key: 'secretkey')
              .limitToFirst(3),
          'orderByKey endBefore': (FirebaseDatabase db) =>
              db.ref('users').orderByKey().endBefore(secret),
          'orderByValue startAfter': (FirebaseDatabase db) =>
              db.ref('users').orderByValue().startAfter(secret),
        };

    queries.forEach((String name, Query Function(FirebaseDatabase db) build) {
      timed(name, (FakeTime time) {
        final _Wire w = _Wire(time);
        w.failedGet(build(w.db), status: 'permission_denied', data: 'denied');
        for (final String message in w.messages) {
          expect(message, isNot(contains(secret)), reason: message);
          expect(message, isNot(contains('secretkey')), reason: message);
        }
        expect(
          w.messages,
          contains(
            allOf(
              startsWith('debug: get for query /users ('),
              contains('permission_denied'),
            ),
          ),
        );
      });
    });

    timed('the line holds the index, the bounds that are set and the limit', (
      FakeTime time,
    ) {
      final _Wire w = _Wire(time);
      w.failedGet(
        w.db.ref('users').orderByChild('email').equalTo(secret),
        status: 'permission_denied',
      );
      w.failedGet(
        w.db.ref('users').orderByKey().startAfter(secret).limitToLast(5),
        status: 'permission_denied',
      );
      expect(
        w.messages.where((String m) => m.contains('get for query')),
        <String>[
          'debug: get for query /users (order email, start inclusive, end '
              'inclusive) failed: ServerActionsException(permission_denied)',
          'debug: get for query /users (order .key, start exclusive, limit 5 '
              'last) failed: ServerActionsException(permission_denied)',
        ],
      );
    });
  });

  // Mutation D: in core/repo_server_actions.dart `onDataUpdate`, log `$e` in place of
  // `${e.runtimeType}`.
  group('data the client cannot read is logged by error type', () {
    // A bool priority is invalid: nodeFromJson throws an ArgumentError that quotes it.
    const Map<String, Object?> unreadable = <String, Object?>{
      '.value': 'secret-value',
      '.priority': true,
    };

    timed('in a get answer', (FakeTime time) {
      final _Wire w = _Wire(time);
      w.failedGet(w.db.ref('a'), status: 'ok', data: unreadable);
      expect(
        w.messages,
        contains(
          'error: Failed to parse server response for get() at /a: '
          'ArgumentError',
        ),
      );
      for (final String message in w.messages) {
        expect(message, isNot(contains('secret-value')), reason: message);
      }
    });

    timed('in a data push', (FakeTime time) {
      final _Wire w = _Wire(time);
      // Straight to the delegate: the fake's own store refuses the data first.
      w.server.delegate!.onDataUpdate('/a', unreadable, isMerge: false);
      time.elapse(Duration.zero);
      expect(
        w.messages,
        contains('error: FIREBASE INTERNAL ERROR at /a: ArgumentError'),
      );
      for (final String message in w.messages) {
        expect(message, isNot(contains('secret-value')), reason: message);
      }
    });
  });

  // Mutation E: in realtime/database_url.dart `parseDatabaseUrl`, put back the old text of the
  // http error ('... only reachable through useEmulator (emulatorDatabase)').
  group('an http database URL names emulatorHost', () {
    for (final String url in <String>[
      'http://x.firebaseio.com',
      'ws://x.firebaseio.com',
      'http://127.0.0.1:9000?ns=x',
    ]) {
      test(url, () {
        expect(
          () => FirebaseDatabase(newTestApp(), databaseUrl: url),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              allOf(
                contains('emulatorHost'),
                contains('useDatabaseEmulator'),
                isNot(contains('useEmulator')),
                isNot(contains(url)),
              ),
            ),
          ),
        );
      });
    }

    test('the same URL works with emulatorHost', () {
      final FirebaseDatabase db = FirebaseDatabase(
        newTestApp(),
        databaseUrl: 'http://127.0.0.1:9000?ns=x',
        emulatorHost: '127.0.0.1:9000',
      );
      expect(db.databaseUrl, Uri.parse('http://127.0.0.1:9000?ns=x'));
    });
  });

  // Mutation N: in api/firebase_database.dart `refFromUrl`, drop the namespace comparison
  // (`if (namespace != null && namespace != here.namespace)` becomes `if (false)`).
  group('refFromUrl compares the namespace and quotes no URL', () {
    Matcher argumentErrorWithout(List<String> parts) => throwsA(
      isA<ArgumentError>().having(
        (ArgumentError e) => e.toString(),
        'text',
        allOf(<Matcher>[for (final String p in parts) isNot(contains(p))]),
      ),
    );

    test('a custom domain with ?ns=', () {
      final FirebaseDatabase db = FirebaseDatabase(
        newTestApp(),
        databaseUrl: 'https://db.example.com?ns=alpha',
      );
      expect(db.refFromUrl('https://db.example.com/a/b?ns=alpha').path, '/a/b');
      expect(db.refFromUrl('https://db.example.com/a/b?ns=Alpha').path, '/a/b');
      expect(
        () => db.refFromUrl('https://db.example.com/a/b?ns=beta'),
        argumentErrorWithout(<String>['beta']),
      );
    });

    test('a firebaseio.com host with another ?ns=', () {
      final FirebaseDatabase db = FirebaseDatabase(newTestApp());
      expect(
        () => db.refFromUrl(
          'https://test-project-default-rtdb.firebaseio.com/a?ns=beta',
        ),
        argumentErrorWithout(<String>['beta']),
      );
      expect(
        db
            .refFromUrl(
              'https://test-project-default-rtdb.firebaseio.com/a'
              '?ns=test-project-default-rtdb',
            )
            .path,
        '/a',
      );
    });

    test('on the emulator, a namespace in the URL must be this one', () {
      final FirebaseDatabase db = FirebaseDatabase(
        newTestApp(),
        emulatorHost: '127.0.0.1:9000',
      );
      expect(
        () => db.refFromUrl('http://127.0.0.1:9000/c?ns=x'),
        argumentErrorWithout(<String>['?ns=x']),
      );
      expect(
        () => db.refFromUrl('https://other.firebaseio.com/c'),
        throwsArgumentError,
      );
      expect(
        db
            .refFromUrl('http://127.0.0.1:9000/c?ns=test-project-default-rtdb')
            .path,
        '/c',
      );
      expect(db.refFromUrl('http://localhost:9000/c').path, '/c');
      expect(
        db
            .refFromUrl('https://test-project-default-rtdb.firebaseio.com/c')
            .path,
        '/c',
      );
    });

    test('no error quotes user info, the URL or its path', () {
      final FirebaseDatabase db = FirebaseDatabase(newTestApp());
      final FirebaseDatabase emulator = FirebaseDatabase(
        newTestApp(),
        emulatorHost: '127.0.0.1:9000',
      );
      const List<String> hidden = <String>['secret', 'user:', 'private-path'];
      for (final String url in <String>[
        'https://user:secret@test-project-default-rtdb.firebaseio.com/private-path%ZZ',
        'https://user:secret@test-project-default-rtdb.firebaseio.com/private-path',
        'https://user:secret@other.firebaseio.com/private-path',
        'https://test-project-default-rtdb.firebaseio.com/private-path?ns=secret',
      ]) {
        expect(() => db.refFromUrl(url), argumentErrorWithout(hidden));
      }
      for (final String url in <String>[
        'http://user:secret@127.0.0.1:9000/private-path%ZZ',
        'http://user:secret@127.0.0.1:9000/private-path?ns=secret',
      ]) {
        expect(() => emulator.refFromUrl(url), argumentErrorWithout(hidden));
      }
    });
  });
}
