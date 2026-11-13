// Fuzz: DocumentSnapshot.fromJson and QuerySnapshot.fromJson on malformed
// JSON objects.
//
// The JSON of a snapshot (toJson) is meant to travel, from a server to a
// client for example, so fromJson reads untrusted input. The JSON objects of
// generated snapshots are mutated (the fields, and the bundle string inside
// them, see bundle_fuzz_test.dart). fromJson must return a snapshot whose data
// can be read, or throw a FirestoreError; never another error, and never hang.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_builder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:test/test.dart';

import '../../util/fuzz.dart';
import '../../util/property.dart';
import '../../util/property_model.dart';
import 'bundle_fuzz_test.dart' show hostileBundle, hostileJson, validBundle;

/// The JSON of a snapshot, as a document snapshot or a query snapshot writes
/// it, around [bundle].
Map<String, Object?> snapshotJson(
  Gen gen,
  String bundle, {
  required bool query,
}) => <String, Object?>{
  'type': query ? QuerySnapshot.jsonType : DocumentSnapshot.jsonType,
  'bundleSource': query ? 'QuerySnapshot' : 'DocumentSnapshot',
  'bundleName': query ? 'q1' : gen.documentKey().path.canonicalString,
  'bundle': bundle,
};

/// The bundle of a query snapshot: one named query (`q1`), with the
/// generated documents that match it.
String validQueryBundle(Gen gen) {
  Query query;
  do {
    query = gen.query();
  } while (query.isDocumentQuery || query.isCollectionGroupQuery);
  final List<Document> documents = <Document>[
    for (int i = 0; i < 6; i++) gen.document(),
  ].where(query.matches).toList();
  return (BundleBuilder(
    RemoteSerializer(modelDatabaseId),
    'b',
  )..addNamedQuery('q1', query, documents, gen.snapshotVersion())).build();
}

/// A malformed snapshot JSON object.
Map<String, Object?> hostileSnapshotJson(Gen gen) {
  final bool query = gen.chance(50);
  final Uint8List bundle = switch (gen.below(3)) {
    0 => utf8.encode(validBundle(gen)),
    1 => utf8.encode(validQueryBundle(gen)),
    _ => hostileBundle(gen),
  };
  final Map<String, Object?> json = snapshotJson(
    gen,
    utf8.decode(bundle, allowMalformed: true),
    query: query,
  );
  for (int i = gen.below(3); i > 0; i--) {
    final String key = gen.pick(const <String>[
      'type', 'bundleSource', 'bundleName', 'bundle', 'extra', //
    ]);
    switch (gen.below(4)) {
      case 0:
        json.remove(key);
        break;
      case 1:
        json[key] = hostileJson(gen);
        break;
      case 2:
        json[key] = gen.pick(const <String>[
          '',
          'NOT SUPPORTED',
          'firestore/documentSnapshot/1.0',
          'firestore/querySnapshot/1.0',
          'DocumentSnapshot',
          'QuerySnapshot',
          'c',
          'c/d',
          'c/d/e',
          '/c/d',
          'c//d',
          'q1',
          'q2',
          '0{}',
          '1{',
        ]);
        break;
      default:
        // Keep the field.
        break;
    }
  }
  return json;
}

void main() {
  test('fromJson of valid snapshot JSON', () {
    forAll<Map<String, Object?>>(
      'valid snapshot JSON',
      count: cases(100),
      generate: (Gen gen) =>
          snapshotJson(gen, validQueryBundle(gen), query: true),
      check: (Map<String, Object?> json) {
        final QuerySnapshot<Map<String, Object?>> snapshot =
            QuerySnapshot<Map<String, Object?>>.fromJson(modelFirestore, json);
        for (final DocumentSnapshot<Map<String, Object?>> document
            in snapshot.docs) {
          expect(document.data, isA<Map<String, Object?>>());
        }
      },
    );
  });

  test('fromJson of malformed snapshot JSON throws a FirestoreError', () {
    forAll<Map<String, Object?>>(
      'malformed snapshot JSON',
      count: cases(1500),
      generate: hostileSnapshotJson,
      show: (Map<String, Object?> json) => '$json',
      check: (Map<String, Object?> json) {
        final Stopwatch watch = Stopwatch()..start();
        if (json['bundleSource'] == 'QuerySnapshot' ||
            json['type'] == QuerySnapshot.jsonType) {
          final QuerySnapshot<Map<String, Object?>>? snapshot =
              acceptOrRejectFirestore(
                () => QuerySnapshot<Map<String, Object?>>.fromJson(
                  modelFirestore,
                  json,
                ),
                () => '$json',
              );
          if (snapshot != null) {
            expect(snapshot.query, isNotNull);
            for (final DocumentSnapshot<Map<String, Object?>> document
                in snapshot.docs) {
              acceptOrReject(
                () => document.data,
                () => document.reference.path,
              );
            }
          }
        } else {
          final DocumentSnapshot<Map<String, Object?>>? snapshot =
              acceptOrRejectFirestore(
                () => DocumentSnapshot<Map<String, Object?>>.fromJson(
                  modelFirestore,
                  json,
                ),
                () => '$json',
              );
          if (snapshot != null) {
            acceptOrReject(
              () => snapshot.data,
              () => snapshot.reference.path,
            );
          }
        }
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      },
    );
  });
}

/// [acceptOrReject] for the public API: the only clean rejection is a
/// [FirestoreError].
T? acceptOrRejectFirestore<T>(T Function() body, String Function() input) {
  try {
    return body();
  } on FirestoreError catch (error) {
    final Object? cause = error.cause;
    if (cause != null &&
        !isCleanRejection(cause, error.stackTrace ?? StackTrace.empty)) {
      fail(
        'fromJson failed with ${cause.runtimeType}: $cause\n  input: ${input()}',
      );
    }
    return null;
  }
}
