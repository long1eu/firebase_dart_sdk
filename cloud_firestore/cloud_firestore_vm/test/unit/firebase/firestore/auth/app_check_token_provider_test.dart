// Copyright 2018 Google LLC
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

class FakeAppCheck implements InternalAppCheckTokenProvider {
  final List<bool> forceRefreshArgs = <bool>[];
  final StreamController<AppCheckTokenResult> changes =
      StreamController<AppCheckTokenResult>.broadcast();
  Object? throwError;
  AppCheckTokenResult result = const AppCheckTokenResult('token-1');

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    forceRefreshArgs.add(forceRefresh);
    if (throwError != null) {
      throw throwError!;
    }
    return result;
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged => changes.stream;
}

Future<Map<String, String>> _metadata(ChannelOptionsProvider provider) async {
  final Map<String, String> metadata = <String, String>{};
  for (final MetadataProvider p in provider.callOptions.metadataProviders) {
    await p(metadata, 'uri');
  }
  return metadata;
}

ChannelOptionsProvider _options(AppCheckTokenProvider? appCheck) =>
    ChannelOptionsProvider(
      databaseId: DatabaseId.forDatabase('p', 'd'),
      credentialsProvider: EmptyCredentialsProvider(),
      appCheckProvider: appCheck,
    );

void main() {
  test('header is present when a provider is set', () async {
    final FakeAppCheck fake = FakeAppCheck();
    final Map<String, String> m =
        await _metadata(_options(AppCheckTokenProvider(fake)));
    expect(m['x-firebase-appcheck'], 'token-1');
    expect(m['x-goog-api-client'], isNotEmpty);
  });

  test('header is absent when no provider is set', () async {
    final Map<String, String> m = await _metadata(_options(null));
    expect(m.containsKey('x-firebase-appcheck'), isFalse);
    expect(m['x-goog-request-params'], 'projects/p/databases/d');
  });

  test('header is absent for an empty token or an unavailable provider',
      () async {
    final FakeAppCheck fake = FakeAppCheck()
      ..result = const AppCheckTokenResult('');
    expect(
        (await _metadata(_options(AppCheckTokenProvider(fake))))
            .containsKey('x-firebase-appcheck'),
        isFalse);
    // No interop provider registered on the app: ignored, not an error.
    expect(
        (await _metadata(_options(AppCheckTokenProvider(null))))
            .containsKey('x-firebase-appcheck'),
        isFalse);
  });

  test('a placeholder token with an error is still sent (like upstream)',
      () async {
    final FakeAppCheck fake = FakeAppCheck()
      ..result = AppCheckTokenResult('placeholder', error: StateError('x'));
    final Map<String, String> m =
        await _metadata(_options(AppCheckTokenProvider(fake)));
    expect(m['x-firebase-appcheck'], 'placeholder');
  });

  test('a failing provider fails the RPC with UNAUTHENTICATED', () async {
    final FakeAppCheck fake = FakeAppCheck()..throwError = StateError('boom');
    await expectLater(
      _metadata(_options(AppCheckTokenProvider(fake))),
      throwsA(isA<GrpcError>()
          .having((GrpcError e) => e.code, 'code', StatusCode.unauthenticated)),
    );
  });

  test('invalidateToken forces a refresh on the next request only', () async {
    final FakeAppCheck fake = FakeAppCheck();
    final ChannelOptionsProvider options =
        _options(AppCheckTokenProvider(fake));
    await _metadata(options);
    options.invalidateToken();
    await _metadata(options);
    await _metadata(options);
    expect(fake.forceRefreshArgs, <bool>[false, true, false]);
  });

  test('token changes are forwarded and stop after close', () async {
    final FakeAppCheck fake = FakeAppCheck();
    final AppCheckTokenProvider provider = AppCheckTokenProvider(fake);
    final List<String> seen = <String>[];
    provider.onChange.listen(seen.add);

    fake.changes.add(const AppCheckTokenResult('t2'));
    await Future<void>.delayed(Duration.zero);
    expect(seen, <String>['t2']);

    await provider.close();
    expect(fake.changes.hasListener, isFalse);
  });
}
