// Owner K. Threat model T13 and T14, the token and backoff rows of limits_test.dart, at the level
// of ReconnectBackoff, AuthSession and ProviderTokenSource (the persistent connection wires them;
// its own limits tests are P's).
import 'dart:convert';

import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/reconnect_backoff.dart';
import 'package:test/test.dart';

import '../util/fakes.dart';

String _idToken() {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'none'})}.'
      '${part(<String, Object?>{'sub': 'u1', 'iat': 1})}.';
}

void main() {
  // The unit only: these two tests pin ReconnectBackoff. Whether PersistentConnection calls
  // markEstablished at the right moment is pinned in p_limits_test.dart (hello then drop, two
  // pushes without an ok answer) and p_server_input_test.dart (a protocol error).
  test(
    'ReconnectBackoff: without markEstablished the delays grow to the cap (T13)',
    () {
      DateTime now = DateTime.utc(2026, 11, 22);
      final ReconnectBackoff backoff = ReconnectBackoff(
        min: const Duration(seconds: 1),
        max: const Duration(seconds: 30),
        multiplier: 1.3,
        resetAfter: const Duration(seconds: 30),
        now: () => now,
        random: () => 1,
      );
      final List<int> delays = <int>[];
      for (int i = 0; i < 20; i++) {
        final DateTime started = now;
        now = now.add(const Duration(milliseconds: 100));
        final Duration delay = backoff.nextDelay(attemptStartedAt: started);
        delays.add(delay.inMilliseconds);
        now = now.add(delay);
      }
      expect(delays.first, 900);
      for (int i = 1; i < 14; i++) {
        expect(delays[i], greaterThan(delays[i - 1]), reason: '$delays');
      }
      expect(delays.last, 29900);
    },
  );

  test(
    'ReconnectBackoff: markEstablished resets the bound only after resetAfter (T13)',
    () {
      DateTime now = DateTime.utc(2026, 11, 22);
      ReconnectBackoff backoff() => ReconnectBackoff(
        min: const Duration(seconds: 1),
        max: const Duration(seconds: 30),
        multiplier: 2,
        resetAfter: const Duration(seconds: 30),
        now: () => now,
        random: () => 1,
      );
      Duration grow(ReconnectBackoff b) {
        Duration last = Duration.zero;
        for (int i = 0; i < 4; i++) {
          last = b.nextDelay(attemptStartedAt: now);
        }
        return last;
      }

      final ReconnectBackoff early = backoff();
      expect(grow(early), const Duration(seconds: 8));
      early.markEstablished();
      now = now.add(const Duration(seconds: 29));
      // Established 29 s ago: no reset, the delay is the grown bound of 16 s.
      expect(
        early.nextDelay(attemptStartedAt: now),
        const Duration(seconds: 16),
      );

      final ReconnectBackoff late = backoff();
      expect(grow(late), const Duration(seconds: 8));
      late.markEstablished();
      now = now.add(const Duration(seconds: 31));
      expect(late.nextDelay(attemptStartedAt: now), const Duration(seconds: 1));
    },
  );

  test('revoke loop: at most one forced refresh per minute (T14)', () async {
    DateTime now = DateTime.utc(2026, 11, 22);
    final FakeAuth auth = FakeAuth(<String?>[_idToken()]);
    final FakeAppCheck appCheck = FakeAppCheck('ac');
    final ProviderTokenSource tokens = ProviderTokenSource(
      auth: auth,
      appCheck: appCheck,
      forcedRefreshMinInterval: const Duration(seconds: 60),
      now: () => now,
    );
    final RecordingSender sender = RecordingSender();
    final AuthSession session = AuthSession(
      sender.send,
      tokens,
      invalidTokenThreshold: 3,
      protocol: const RealtimeProtocol(isUsingEmulator: false),
      onAuthStatus: (_, _) {},
      onAppCheckStatus: (_, _) {},
    );
    // A hostile server answers every auth with invalid_token, every 5 s, for 3 minutes.
    for (int attempt = 0; attempt < 36; attempt++) {
      final bool force = session.forceRefreshNext;
      session.authChanged(await tokens.authToken(forceRefresh: force));
      session.appCheckChanged(await tokens.appCheckToken(forceRefresh: force));
      session.onConnected();
      sender.respond(sender.sent.length - 2, 'invalid_token', 'no');
      session.onDisconnected();
      now = now.add(const Duration(seconds: 5));
    }
    final int forcedAuth = auth.calls.where((bool f) => f).length;
    final int forcedAppCheck = appCheck.calls.where((bool f) => f).length;
    expect(auth.calls, hasLength(36));
    expect(forcedAuth, 3);
    expect(forcedAppCheck, 3);
    expect(session.invalidTokenThresholdReached, isTrue);
  });

  test('the invalid-token threshold puts the backoff at its cap (8.3)', () {
    final DateTime now = DateTime.utc(2026, 11, 22);
    final ReconnectBackoff backoff = ReconnectBackoff(
      min: const Duration(seconds: 1),
      max: const Duration(seconds: 30),
      multiplier: 1.3,
      resetAfter: const Duration(seconds: 30),
      now: () => now,
      random: () => 1,
    );
    final RecordingSender sender = RecordingSender();
    final AuthSession session = AuthSession(
      sender.send,
      FakeTokenSource(),
      invalidTokenThreshold: 3,
      protocol: const RealtimeProtocol(isUsingEmulator: false),
      onAuthStatus: (_, _) {},
      onAppCheckStatus: (_, _) {},
    );
    for (int i = 0; i < 3; i++) {
      session.onAuthRevoked('invalid_token', '');
    }
    expect(session.invalidTokenThresholdReached, isTrue);
    backoff.setToMax();
    expect(
      backoff.nextDelay(attemptStartedAt: now),
      const Duration(seconds: 30),
    );
  });
}
