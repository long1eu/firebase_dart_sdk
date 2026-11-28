import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

const String _sentinel = 'SENTINEL-secret-token-123';

/// Extends the base class and overrides only the two abstract members.
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

class _SecretError implements Exception {
  @override
  String toString() => 'failed with $_sentinel';
}

void main() {
  group('5.2 default getLimitedUseToken', () {
    test('5.2 gives an empty token and an UnsupportedError', () async {
      final _SessionOnlyProvider provider = _SessionOnlyProvider();
      addTearDown(provider.changes.close);

      final AppCheckTokenResult result = await provider.getLimitedUseToken();

      expect(result.token, isEmpty);
      expect(result.error, isA<UnsupportedError>());
      expect(
        (result.error! as UnsupportedError).message,
        'This App Check provider does not give limited-use tokens. '
        'Override getLimitedUseToken().',
      );
    });

    test('5.2 never falls back to getToken', () async {
      final _SessionOnlyProvider provider = _SessionOnlyProvider();
      addTearDown(provider.changes.close);

      await provider.getLimitedUseToken();
      await provider.getLimitedUseToken();

      expect(provider.getTokenCalls, 0);
    });

    test('5.2 emits nothing on onTokenChanged', () async {
      final _SessionOnlyProvider provider = _SessionOnlyProvider();
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
