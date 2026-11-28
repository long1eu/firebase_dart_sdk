import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/src/fid.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

final RegExp _fidPattern = RegExp(r'^[cdef][A-Za-z0-9_-]{21}$');

Uint8List Function(int length) _bytesFrom(Random random) =>
    (int length) => Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );

/// The first byte encoded in [fid] (its first four characters are the first three bytes).
int _firstByte(String fid) => base64Url.decode(fid.substring(0, 4))[0];

void main() {
  test('5.3 FID: 10 000 FIDs are valid and distinct', () {
    final Uint8List Function(int length) bytes = _bytesFrom(Random.secure());
    final Set<String> fids = <String>{};
    for (int i = 0; i < 10000; i++) {
      final String fid = generateFid(bytes);
      expect(fid, hasLength(22));
      expect(fid, matches(_fidPattern));
      expect(isValidFid(fid), isTrue);
      fids.add(fid);
    }
    expect(fids, hasLength(10000));
  });

  test('5.3 FID: the first nibble is 0111 for every first byte', () {
    for (int byte0 = 0; byte0 < 256; byte0++) {
      final String fid = generateFid(
        (int length) => Uint8List(length)..[0] = byte0,
      );
      final int first = _firstByte(fid);
      expect(first >> 4, 0x7, reason: 'byte0 $byte0');
      expect(first & 0x0F, byte0 & 0x0F, reason: 'byte0 $byte0');
      expect(fid, matches(_fidPattern), reason: 'byte0 $byte0');
    }
  });

  test('5.3 FID: the 17 random bytes become the FID (all-0xFF bytes)', () {
    final String fid = generateFid(
      (int length) => Uint8List.fromList(List<int>.filled(length, 0xFF)),
    );
    expect(fid, 'f${'_' * 21}');
  });

  test('5.3 FID: FirebaseInstallations draws the FID from randomBytes', () {
    fakeAsync((FakeAsync async) {
      final FakeFis fis = FakeFis();
      final FirebaseApp app = newFisApp();
      Uint8List fixed(int length) =>
          Uint8List.fromList(List<int>.generate(length, (int i) => i * 13));
      final FirebaseInstallations installations = FirebaseInstallations(
        app,
        store: MemoryKeyValueStore(),
        httpClient: fis.client,
        randomBytes: fixed,
      );
      final Outcome<String> id = Outcome<String>(installations.getId());
      async.flushMicrotasks();
      expect(id.value, generateFid(fixed));
      installations.close();
      app.delete();
      async.flushMicrotasks();
    });
  });

  test('5.3 FID: default randomness is Random.secure() (fresh, unrepeated '
      'bytes for each installation)', () {
    // Random.secure() itself cannot be observed; the test pins what it gives: every instance created
    // without randomBytes draws a new, valid FID, and the free low nibble of the first byte takes
    // all 16 values over 500 FIDs (a missing value has a probability of about 1e-13).
    fakeAsync((FakeAsync async) {
      final FakeFis fis = FakeFis();
      final FirebaseApp app = newFisApp();
      final List<FirebaseInstallations> instances = <FirebaseInstallations>[];
      final List<Outcome<String>> ids = <Outcome<String>>[];
      for (int i = 0; i < 500; i++) {
        final FirebaseInstallations installations = FirebaseInstallations(
          app,
          store: MemoryKeyValueStore(),
          httpClient: fis.client,
        );
        instances.add(installations);
        ids.add(Outcome<String>(installations.getId()));
      }
      async.flushMicrotasks();
      final Set<String> fids = <String>{
        for (final Outcome<String> id in ids) id.value,
      };
      expect(fids, hasLength(500));
      for (final String fid in fids) {
        expect(fid, matches(_fidPattern));
      }
      final Set<int> lowNibbles = <int>{
        for (final String fid in fids) _firstByte(fid) & 0x0F,
      };
      expect(lowNibbles, hasLength(16));
      for (final FirebaseInstallations installations in instances) {
        installations.close();
      }
      app.delete();
      async.flushMicrotasks();
    });
  });
}
