// Copyright 2024 Google LLC
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/globals_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:test/test.dart';

/// Defines the tests for any implementation of the [GlobalsCache] interface (port of the Android `GlobalsCacheTest`
/// and the JS `globals_cache.test.ts`).
///
/// [createPersistence] creates and starts the [Persistence] under test. It is called once per test.
void defineGlobalsCacheTests(Future<Persistence> Function() createPersistence) {
  late Persistence persistence;
  late GlobalsCache globalsCache;

  setUp(() async {
    persistence = await createPersistence();
    globalsCache = persistence.globalsCache;
  });

  tearDown(() => persistence.shutdown());

  Future<T> inTransaction<T>(Future<T> Function() action) =>
      persistence.runTransactionAndReturn<T>('globals cache test', action);

  test('setAndGetDbToken', () async {
    final Uint8List value = Uint8List.fromList(utf8.encode('TestData'));
    await inTransaction(() => globalsCache.setSessionToken(value));
    expect(await inTransaction(globalsCache.getSessionToken), value);
  });

  test('setAndGetEmptyDbToken', () async {
    await inTransaction(() => globalsCache.setSessionToken(Uint8List(0)));
    expect(await inTransaction(globalsCache.getSessionToken), isEmpty);
  });

  // Not in Android's test; covered by the empty default of the JS and Android implementations.
  test('returns an empty token when none was stored', () async {
    expect(await inTransaction(globalsCache.getSessionToken), isEmpty);
  });

  test('the last stored token wins', () async {
    await inTransaction(
      () => globalsCache.setSessionToken(Uint8List.fromList(<int>[1, 2])),
    );
    await inTransaction(
      () => globalsCache.setSessionToken(Uint8List.fromList(<int>[3])),
    );
    expect(await inTransaction(globalsCache.getSessionToken), <int>[3]);
  });
}
