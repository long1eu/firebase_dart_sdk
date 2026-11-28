import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

const String _sentinel = 'SENTINEL-secret-token-123';

/// Extends the base class with its two abstract members; no limited-use tokens.
class _SessionOnlyProvider extends AppCheckTokenProvider {
  int getTokenCalls = 0;
  final StreamController<AppCheckTokenResult> changes =
      StreamController<AppCheckTokenResult>.broadcast();

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    getTokenCalls++;
    return const AppCheckTokenResult('session-token');
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged => changes.stream;
}

/// Extends the session-only provider and adds the limited-use interface.
class _LimitedUseProvider extends _SessionOnlyProvider
    implements LimitedUseAppCheckTokenProvider {
  @override
  Future<AppCheckTokenResult> getLimitedUseToken() async {
    return const AppCheckTokenResult('limited-token');
  }
}

/// Only implements the interface: exactly its two instance members.
class _ImplementsOnlyProvider implements AppCheckTokenProvider {
  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    return const AppCheckTokenResult('implemented-token');
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

class _SecretError implements Exception {
  @override
  String toString() => 'failed with $_sentinel';
}

void main() {
  group('5.2 LimitedUseAppCheckTokenProvider', () {
    test('5.2 a session-only provider is not one', () {
      final _SessionOnlyProvider provider = _SessionOnlyProvider();
      addTearDown(provider.changes.close);

      expect(provider, isNot(isA<LimitedUseAppCheckTokenProvider>()));
    });

    test('5.2 a provider that also implements the interface is one', () async {
      final _LimitedUseProvider provider = _LimitedUseProvider();
      addTearDown(provider.changes.close);

      expect(provider, isA<LimitedUseAppCheckTokenProvider>());
      expect((await provider.getLimitedUseToken()).token, 'limited-token');
      expect(provider.getTokenCalls, 0);
    });

    test('5.2 getLimitedUseToken emits nothing on onTokenChanged', () async {
      final _LimitedUseProvider provider = _LimitedUseProvider();
      addTearDown(provider.changes.close);
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

  group('5.2 AppCheckTokenProvider contract', () {
    test('5.2 S4 responseDeadline is 8 seconds', () {
      expect(
        AppCheckTokenProvider.responseDeadline,
        const Duration(seconds: 8),
      );
    });

    test('5.2 a class that only implements the base keeps compiling', () async {
      final AppCheckTokenProvider provider = _ImplementsOnlyProvider();

      expect(provider, isNot(isA<LimitedUseAppCheckTokenProvider>()));
      expect(
        (await provider.getToken(forceRefresh: false)).token,
        'implemented-token',
      );
      expect(await provider.onTokenChanged.isEmpty, isTrue);
    });
  });

  group('5.2 AppCheckTokenResult.failure', () {
    test('5.2 carries the placeholder token and the identical error', () {
      final Object error = StateError('boom');

      final AppCheckTokenResult result = AppCheckTokenResult.failure(error);

      expect(result.token, AppCheckTokenResult.placeholderToken);
      expect(result.error, same(error));
    });

    test('5.2 is const-constructible', () {
      const AppCheckTokenResult a = AppCheckTokenResult.failure('e');
      const AppCheckTokenResult b = AppCheckTokenResult.failure('e');

      expect(identical(a, b), isTrue);
      expect(a.token, AppCheckTokenResult.placeholderToken);
    });

    test('5.2 placeholderToken decodes to {"error":"UNKNOWN_ERROR"}', () {
      final String decoded = utf8.decode(
        base64.decode(AppCheckTokenResult.placeholderToken),
      );

      expect(decoded, '{"error":"UNKNOWN_ERROR"}');
      expect(jsonDecode(decoded), <String, Object?>{'error': 'UNKNOWN_ERROR'});
    });
  });

  group('5.2 AppCheckTokenResult.toString', () {
    test('5.2 success shape redacts the token', () {
      const AppCheckTokenResult result = AppCheckTokenResult(_sentinel);

      expect(result.toString(), 'AppCheckTokenResult(token: <redacted>)');
      expect(result.toString(), isNot(contains(_sentinel)));
    });

    test('5.2 error shape names the runtime type, not the text', () {
      final AppCheckTokenResult result = AppCheckTokenResult(
        _sentinel,
        error: _SecretError(),
      );

      expect(
        result.toString(),
        'AppCheckTokenResult(token: <redacted>, error: _SecretError)',
      );
      expect(result.toString(), isNot(contains(_sentinel)));
    });

    test('5.2 failure shape never shows the error text', () {
      final AppCheckTokenResult result = AppCheckTokenResult.failure(
        StateError(_sentinel),
      );

      expect(
        result.toString(),
        'AppCheckTokenResult(token: <redacted>, error: StateError)',
      );
      expect(result.toString(), isNot(contains(_sentinel)));
      expect(
        result.toString(),
        isNot(contains(AppCheckTokenResult.placeholderToken)),
      );
    });
  });
}
