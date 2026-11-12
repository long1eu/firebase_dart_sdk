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

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:test/test.dart';

/// Ported from upstream FirebaseFirestoreSettingsTest (current `main`), minus
/// the Builder and legacy cache config cases which do not exist in the port.
void main() {
  const int oneMb = 1024 * 1024;

  test('settings with no modifications are the defaults', () {
    final FirestoreSettings settings = FirestoreSettings();
    expect(settings.host, 'firestore.googleapis.com');
    expect(settings.port, 443);
    expect(settings.sslEnabled, isTrue);
    expect(settings.persistenceEnabled, isTrue);
    expect(settings.cacheSizeBytes, 100 * oneMb);
    expect(FirestoreSettings.defaultCacheSizeBytes, 100 * oneMb);
  });

  test('settings with all values customized keep those values', () {
    final FirestoreSettings settings = FirestoreSettings(
      host: 'a.b.c',
      port: 8080,
      sslEnabled: false,
      persistenceEnabled: false,
      cacheSizeBytes: 3 * oneMb,
    );
    expect(settings.host, 'a.b.c');
    expect(settings.port, 8080);
    expect(settings.sslEnabled, isFalse);
    expect(settings.persistenceEnabled, isFalse);
    expect(settings.cacheSizeBytes, 3 * oneMb);
  });

  test('copyWith copies all values and replaces the given ones', () {
    final FirestoreSettings original = FirestoreSettings(
      host: 'a.b.c',
      port: 8080,
      sslEnabled: false,
      persistenceEnabled: false,
      cacheSizeBytes: 3 * oneMb,
    );
    expect(original.copyWith(), original);
    expect(original.copyWith().hashCode, original.hashCode);

    final FirestoreSettings changed = original.copyWith(
        host: 'x.y.z',
        port: 1,
        sslEnabled: true,
        persistenceEnabled: true,
        cacheSizeBytes: 5 * oneMb);
    expect(changed.host, 'x.y.z');
    expect(changed.port, 1);
    expect(changed.sslEnabled, isTrue);
    expect(changed.persistenceEnabled, isTrue);
    expect(changed.cacheSizeBytes, 5 * oneMb);
    expect(changed, isNot(original));
  });

  test('equality considers every property', () {
    final FirestoreSettings base = FirestoreSettings(host: 'a.b');
    expect(FirestoreSettings(host: 'a.b'), base);
    expect(FirestoreSettings(host: 'a.b', port: 1), isNot(base));
    expect(FirestoreSettings(host: 'a.c'), isNot(base));
    expect(FirestoreSettings(host: 'a.b', sslEnabled: false), isNot(base));
    expect(
        FirestoreSettings(host: 'a.b', persistenceEnabled: false), isNot(base));
    expect(
        FirestoreSettings(host: 'a.b', cacheSizeBytes: 2 * oneMb), isNot(base));
  });

  test('toString lists the properties', () {
    final String text = FirestoreSettings(host: 'a.b').toString();
    expect(text, contains('a.b'));
    expect(text, contains('443'));
  });

  group('validation (Java throws unconditionally)', () {
    test('ssl cannot be disabled for the default host', () {
      expect(() => FirestoreSettings(sslEnabled: false), throwsA(anything));
    });

    test('unlimited cache size is accepted', () {
      expect(
          FirestoreSettings(
                  cacheSizeBytes: FirestoreSettings.cacheSizeUnlimited)
              .cacheSizeBytes,
          FirestoreSettings.cacheSizeUnlimited);
    });

    test('a cache size below the 1 MB minimum is rejected', () {
      expect(() => FirestoreSettings(cacheSizeBytes: oneMb - 1),
          throwsA(anything));
    });

    test('a cache size of exactly 1 MB is accepted (Java rejects only < 1 MB)',
        () {
      expect(FirestoreSettings(cacheSizeBytes: oneMb).cacheSizeBytes, oneMb);
    });
  });
}
