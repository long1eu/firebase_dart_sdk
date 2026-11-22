// The error table, the same-object rule for programmer errors, and stream
// errors.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/errors.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

fs.FirebaseDatabaseException clientError(String code) =>
    fs.FirebaseDatabaseException(code: code, message: 'message of $code');

void main() {
  group('convertError', () {
    test(
      'write-canceled is write-cancelled and operation-failed is failure',
      () {
        expect(
          convertError(clientError('write-canceled')),
          isDatabaseCode('write-cancelled'),
        );
        expect(
          convertError(clientError('operation-failed')),
          isDatabaseCode('failure'),
        );
      },
    );

    test('every other client code passes through with its message', () {
      const List<String> same = <String>[
        'permission-denied',
        'disconnected',
        'max-retries',
        'overridden-by-set',
        'unavailable',
        'network-error',
        'index-not-defined',
        'too-big',
        'database-closed',
        'unknown',
      ];
      for (final String code in same) {
        final Object converted = convertError(clientError(code));
        expect(converted, isDatabaseCode(code));
        expect((converted as FirebaseException).message, 'message of $code');
      }
    });

    test(
      'a code the table does not know is unknown, with the client message',
      () {
        final Object converted = convertError(clientError('brand-new'));

        expect(converted, isDatabaseCode('unknown'));
        expect(
          (converted as FirebaseException).message,
          'message of brand-new',
        );
      },
    );

    test(
      'keeps the stack trace of the client exception, else the given one',
      () {
        final StackTrace own = StackTrace.current;
        final StackTrace given = StackTrace.fromString('given');

        final FirebaseException withOwn =
            convertError(
                  fs.FirebaseDatabaseException(
                    code: 'unavailable',
                    message: 'm',
                    stackTrace: own,
                  ),
                  given,
                )
                as FirebaseException;
        final FirebaseException withGiven =
            convertError(clientError('unavailable'), given)
                as FirebaseException;

        expect(withOwn.stackTrace, same(own));
        expect(withGiven.stackTrace, same(given));
      },
    );

    test('another firebase_app_dart exception keeps its plugin and code', () {
      const dart_app.FirebaseException auth = dart_app.FirebaseException(
        plugin: 'firebase_auth',
        code: 'user-token-expired',
        message: 'expired',
      );

      final Object converted = convertError(auth);

      expect(
        converted,
        isA<FirebaseException>()
            .having(
              (FirebaseException e) => e.plugin,
              'plugin',
              'firebase_auth',
            )
            .having(
              (FirebaseException e) => e.code,
              'code',
              'user-token-expired',
            )
            .having(
              (FirebaseException e) => e,
              'type',
              isNot(isA<dart_app.FirebaseException>()),
            ),
      );
    });

    test('programmer errors and handler exceptions are the same object', () {
      final StateError state = StateError('boom');
      final ArgumentError argument = ArgumentError('bad key');
      final Object custom = Object();

      expect(convertError(state), same(state));
      expect(convertError(argument), same(argument));
      expect(convertError(custom), same(custom));
    });
  });

  group('guard', () {
    test(
      'converts a client exception, with the original stack trace',
      () async {
        final StackTrace trace = StackTrace.current;
        final Future<void> guarded = guard<void>(
          () => Future<void>.error(clientError('write-canceled'), trace),
        );

        await expectLater(guarded, throwsDatabaseCode('write-cancelled'));
      },
    );

    test('rethrows anything else as the same object', () async {
      final StateError error = StateError('boom');

      await expectLater(
        guard<void>(() => Future<void>.error(error)),
        throwsA(same(error)),
      );
    });

    test('a body that throws synchronously fails the Future', () async {
      final ArgumentError error = ArgumentError('bad');

      await expectLater(guard<void>(() => throw error), throwsA(same(error)));
    });

    test('passes the value through', () async {
      expect(await guard<int>(() async => 7), 7);
    });
  });

  group('guardStream', () {
    test('converts errors and passes data and done through', () async {
      final Stream<int> source = Stream<int>.multi((
        MultiStreamController<int> c,
      ) {
        c
          ..add(1)
          ..addError(clientError('permission-denied'))
          ..add(2)
          ..close();
      });
      final List<Object> seen = <Object>[];

      await guardStream(
        source,
      ).handleError((Object e) => seen.add(e)).forEach(seen.add);

      expect(seen, <Object>[1, isDatabaseCode('permission-denied'), 2]);
    });

    test(
      'each listen is one listen of a Stream.multi, not a broadcast',
      () async {
        int listens = 0;
        final Stream<int> source = Stream<int>.multi((
          MultiStreamController<int> c,
        ) {
          listens++;
          c
            ..add(listens)
            ..close();
        });

        final Stream<int> guarded = guardStream(source);
        final List<int> first = await guarded.toList();
        final List<int> second = await guarded.toList();

        expect(guarded.isBroadcast, isFalse);
        expect(listens, 2);
        expect(first, <int>[1]);
        expect(second, <int>[2]);
      },
    );

    test('a broadcast stream stays broadcast', () {
      final StreamController<int> controller =
          StreamController<int>.broadcast();
      addTearDown(controller.close);

      expect(guardStream(controller.stream).isBroadcast, isTrue);
    });
  });

  group('through the official classes', () {
    registerForTests();

    test(
      'a server cancel reaches the listener as permission-denied, then done',
      () async {
        final FirebaseApp app = await newApp();
        final List<Object> log = <Object>[];
        final Completer<void> done = Completer<void>();
        FirebaseDatabase.instanceFor(app: app)
            .ref('s')
            .onValue
            .listen(
              (DatabaseEvent event) => log.add(event.snapshot.value ?? 'null'),
              onError: log.add,
              onDone: done.complete,
            );
        await settle();
        server.answerListen('s', 1);
        await settle();

        server.cancelListen('s', 'permission_denied');
        await done.future;

        expect(log, <Object>[1, isDatabaseCode('permission-denied')]);
      },
    );

    test(
      'a rejected write fails with permission-denied and a message',
      () async {
        final FirebaseApp app = await newApp();
        final Future<void> write = FirebaseDatabase.instanceFor(
          app: app,
        ).ref('denied').set(1);
        await settle();

        server.failLastWrite('permission_denied');

        await expectLater(
          write,
          throwsA(
            allOf(
              isDatabaseCode('permission-denied'),
              isA<FirebaseException>().having(
                (FirebaseException e) => e.message,
                'message',
                isNotEmpty,
              ),
            ),
          ),
        );
      },
    );
  });
}
