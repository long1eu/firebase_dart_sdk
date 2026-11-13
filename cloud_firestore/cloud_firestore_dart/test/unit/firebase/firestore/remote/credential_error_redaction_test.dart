// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Security review L5: the error of an auth or App Check provider is logged and becomes the message of the
// UNAUTHENTICATED error of the call. A provider may quote the token it could not use; it must not reach the log or
// the app's error.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/firestore_call_credentials.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/redact_tokens.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

const String _jwt =
    'eyJhbGciOiJSUzI1NiIsImtpZCI6IjEifQ.eyJzdWIiOiJhbGljZSIsImV4cCI6MX0.c2lnbmF0dXJlLXNpZ25hdHVyZS1zaWduYXR1cmU';
const String _oauth = 'ya29.a0AfH6SMBx3k9Lq2mZ8vT4pR7wN1cY5uJ0hG6fD3sA2qE';

class _FailingCredentials implements CredentialsProvider {
  _FailingCredentials(this.error);

  final Object error;

  @override
  Future<String?> get token => Future<String?>.error(error);

  @override
  void invalidateToken() {}

  @override
  Stream<User> get onChange => Stream<User>.value(User.unauthenticated);
}

class _FailingAppCheck implements InternalAppCheckTokenProvider {
  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) =>
      Future<AppCheckTokenResult>.error(
        StateError('attestation failed for token $_jwt'),
      );

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

Future<List<String>> _printed(Future<void> Function() body) async {
  final List<String> printed = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
          printed.add(line),
    ),
  );
  return printed;
}

void main() {
  group('redactTokens', () {
    test('removes JWTs, labelled tokens and opaque OAuth tokens', () {
      expect(redactTokens('expired: $_jwt'), 'expired: <redacted>');
      expect(
        redactTokens('Authorization: Bearer $_oauth was rejected'),
        'Authorization: Bearer <redacted> was rejected',
      );
      expect(
        redactTokens('refresh failed (token=abcdefghijklmnop1234)'),
        'refresh failed (token=<redacted>)',
      );
      expect(redactTokens('key $_oauth'), 'key <redacted>');
    });

    test('keeps ordinary messages as they are', () {
      for (final String message in <String>[
        'Bad state: no attestation provider',
        'SocketException: Connection refused (OS Error: Connection refused, errno = 61), address = 127.0.0.1',
        'The user token expired at 2026-11-13T10:00:00Z',
        'https://securetoken.googleapis.com/v1/token returned 400',
      ]) {
        expect(redactTokens(message), message);
      }
    });
  });

  test(
    'a failing auth provider: the token in its error is neither logged nor passed on',
    () async {
      final InternalLogLevel level = Log.level;
      Log.level = InternalLogLevel.d;
      addTearDown(() => Log.level = level);
      final FirestoreCallCredentials credentials = FirestoreCallCredentials(
        _FailingCredentials(StateError('token $_jwt was revoked')),
      );
      Object? error;
      final List<String> printed = await _printed(() async {
        try {
          await credentials.getRequestMetadata(<String, String>{}, 'uri');
        } catch (e) {
          error = e;
        }
      });

      expect(
        error,
        isA<GrpcError>()
            .having((GrpcError e) => e.code, 'code', StatusCode.unauthenticated)
            .having(
              (GrpcError e) => e.message,
              'message',
              'Bad state: token <redacted> was revoked',
            ),
      );
      expect(printed, isNotEmpty);
      expect(printed.join('\n'), isNot(contains(_jwt.substring(0, 30))));
      expect(
        printed,
        contains(
          contains(
            'Failed to get token: Bad state: token <redacted> was revoked',
          ),
        ),
      );
    },
  );

  test(
    'a failing App Check provider: the token in its error is not logged',
    () async {
      final FirestoreCallCredentials credentials = FirestoreCallCredentials(
        EmptyCredentialsProvider(),
        appCheckProvider: AppCheckTokenProvider(_FailingAppCheck()),
      );
      final Map<String, String> metadata = <String, String>{};
      final List<String> printed = await _printed(
        () => credentials.getRequestMetadata(metadata, 'uri'),
      );
      expect(metadata.containsKey('x-firebase-appcheck'), isFalse);
      expect(
        printed,
        contains(
          allOf(
            contains('Failed to get AppCheck token'),
            contains('attestation failed'),
          ),
        ),
      );
      expect(printed.join('\n'), isNot(contains(_jwt.substring(0, 30))));
    },
  );
}
