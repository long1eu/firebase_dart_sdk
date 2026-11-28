import 'dart:async';

import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectNoTokenFailure(
  AppCheckTokenResult result, {
  String message = 'firebase_app_check returned no token.',
}) {
  expect(result.token, AppCheckTokenResult.placeholderToken);
  expect(result.error, isA<StateError>());
  expect((result.error! as StateError).message, message);
}

const String _noLimitedUseToken =
    'firebase_app_check returned no limited-use token.';

void main() {
  group('5.5 the base class', () {
    test('5.5 is not a LimitedUseAppCheckTokenProvider', () {
      final FlutterFireAppCheckProvider provider = FlutterFireAppCheckProvider(
        getToken: (bool forceRefresh) async => 'session',
        onTokenChange: const Stream<String?>.empty(),
      );

      expect(provider, isNot(isA<LimitedUseAppCheckTokenProvider>()));
    });
  });

  group('5.5 FlutterFireLimitedUseAppCheckProvider.getLimitedUseToken', () {
    FlutterFireLimitedUseAppCheckProvider build(
      Future<String?> Function() limited, {
      Stream<String?> changes = const Stream<String?>.empty(),
    }) {
      return FlutterFireLimitedUseAppCheckProvider(
        getToken: (bool forceRefresh) async => 'session',
        onTokenChange: changes,
        getLimitedUseToken: limited,
      );
    }

    test('5.5 passes the token through', () async {
      final AppCheckTokenResult result = await build(
        () async => 'limited-1',
      ).getLimitedUseToken();

      expect(result.token, 'limited-1');
      expect(result.error, isNull);
    });

    test('5.5 null gives the placeholder and a StateError', () async {
      _expectNoTokenFailure(
        await build(() async => null).getLimitedUseToken(),
        message: _noLimitedUseToken,
      );
    });

    test('5.5 empty gives the placeholder and a StateError', () async {
      _expectNoTokenFailure(
        await build(() async => '').getLimitedUseToken(),
        message: _noLimitedUseToken,
      );
    });

    test('5.5 a throw gives the placeholder and the thrown error', () async {
      final Exception thrown = Exception('plugin failed');

      final AppCheckTokenResult result = await build(
        () async => throw thrown,
      ).getLimitedUseToken();

      expect(result.token, AppCheckTokenResult.placeholderToken);
      expect(result.error, same(thrown));
    });

    test('5.5 two calls call the callback twice, nothing cached', () async {
      int calls = 0;
      final FlutterFireLimitedUseAppCheckProvider provider = build(
        () async => 'limited-${++calls}',
      );

      final AppCheckTokenResult first = await provider.getLimitedUseToken();
      final AppCheckTokenResult second = await provider.getLimitedUseToken();

      expect(calls, 2);
      expect(first.token, 'limited-1');
      expect(second.token, 'limited-2');
    });

    test('5.5 emits nothing on onTokenChanged', () async {
      final StreamController<String?> source =
          StreamController<String?>.broadcast();
      addTearDown(source.close);
      final FlutterFireLimitedUseAppCheckProvider provider = build(
        () async => 'limited',
        changes: source.stream,
      );
      final List<AppCheckTokenResult> events = <AppCheckTokenResult>[];
      final StreamSubscription<AppCheckTokenResult> sub = provider
          .onTokenChanged
          .listen(events.add);
      addTearDown(sub.cancel);

      await provider.getLimitedUseToken();
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });
  });

  group('5.5 getToken failures', () {
    FlutterFireAppCheckProvider build(Future<String?> Function() session) {
      return FlutterFireAppCheckProvider(
        getToken: (bool forceRefresh) => session(),
        onTokenChange: const Stream<String?>.empty(),
      );
    }

    test('5.5 a throw gives the placeholder and the error', () async {
      final Exception thrown = Exception('plugin failed');

      final AppCheckTokenResult result = await build(
        () async => throw thrown,
      ).getToken(forceRefresh: false);

      expect(result.token, AppCheckTokenResult.placeholderToken);
      expect(result.error, same(thrown));
    });

    test('5.5 null gives the placeholder and an error', () async {
      _expectNoTokenFailure(
        await build(() async => null).getToken(forceRefresh: true),
      );
    });

    test('5.5 empty gives the placeholder and an error', () async {
      _expectNoTokenFailure(
        await build(() async => '').getToken(forceRefresh: false),
      );
    });
  });

  group('5.5 onTokenChanged', () {
    test('5.5 drops null and empty events and carries no errors', () async {
      final StreamController<String?> source = StreamController<String?>();
      addTearDown(source.close);
      final FlutterFireAppCheckProvider provider = FlutterFireAppCheckProvider(
        getToken: (bool forceRefresh) async => 'session',
        onTokenChange: source.stream,
      );
      final List<AppCheckTokenResult> events = <AppCheckTokenResult>[];
      final StreamSubscription<AppCheckTokenResult> sub = provider
          .onTokenChanged
          .listen(events.add);
      addTearDown(sub.cancel);

      source
        ..add('a')
        ..add(null)
        ..add('')
        ..add('b');
      await Future<void>.delayed(Duration.zero);

      expect(events.map((AppCheckTokenResult e) => e.token), <String>[
        'a',
        'b',
      ]);
      expect(events.every((AppCheckTokenResult e) => e.error == null), isTrue);
    });

    test('5.5 is broadcast over a single-subscription source', () async {
      final StreamController<String?> source = StreamController<String?>();
      addTearDown(source.close);
      expect(source.stream.isBroadcast, isFalse);
      final FlutterFireAppCheckProvider provider = FlutterFireAppCheckProvider(
        getToken: (bool forceRefresh) async => 'session',
        onTokenChange: source.stream,
      );
      expect(provider.onTokenChanged.isBroadcast, isTrue);

      final List<String> first = <String>[];
      final List<String> second = <String>[];
      final StreamSubscription<AppCheckTokenResult> a = provider.onTokenChanged
          .listen((AppCheckTokenResult e) => first.add(e.token));
      final StreamSubscription<AppCheckTokenResult> b = provider.onTokenChanged
          .listen((AppCheckTokenResult e) => second.add(e.token));
      addTearDown(a.cancel);
      addTearDown(b.cancel);

      source.add('x');
      await Future<void>.delayed(Duration.zero);

      expect(first, <String>['x']);
      expect(second, <String>['x']);
    });
  });
}
