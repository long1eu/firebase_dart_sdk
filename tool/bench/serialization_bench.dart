// Value serialization benchmark: the time of each step between a user map and the bytes stored in the cache or sent
// to the backend, for a wide document, a document of many small maps in an array, deeply nested maps and a document
// close to the 1 MiB limit.
//
//   dart run serialization_bench.dart [--reps=<n>] [--only=<shape>]
//
// Steps: parse (UserDataConverter.parseSetData), encode (RemoteSerializer.encodeValue of the parsed map), toBytes
// (writeToBuffer), fromBytes (Value.fromBuffer), decode (RemoteSerializer.decodeValue), local (LocalSerializer
// encodeMaybeDocument + writeToBuffer, then fromBuffer + decodeMaybeDocument + data), read (DocumentSnapshot.data()).
// Each number is the median over the repetitions, in milliseconds. Protobuf reads at most 100 nested messages (about
// 33 map levels; the backend allows 20), so the deeper shapes skip the steps that read bytes ("-"): they show how
// the in-memory steps scale with the depth.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;

final DatabaseId databaseId = DatabaseId.forProject('bench');
final RemoteSerializer remote = RemoteSerializer(databaseId);
final LocalSerializer local = LocalSerializer(remote);
final UserDataConverter reader = UserDataConverter(databaseId);
final Firestore firestore = FirestoreInternal.detached(databaseId);
final DocumentKey docKey = DocumentKey.fromPathString('coll/doc');

Map<String, Object?> leaf(int i) => <String, Object?>{
      'name': 'item $i',
      'count': i,
      'price': i * 1.5,
      'active': i.isEven,
      'when': Timestamp(1700000000 + i, 0),
      'where': GeoPoint(i % 90, i % 180),
      'tags': <Object?>['a$i', 'b$i'],
    };

/// 10000 fields of mixed types at the top level.
Map<String, Object?> wide() => <String, Object?>{
      for (int i = 0; i < 10000; i++)
        'field${i.toString().padLeft(5, '0')}': leaf(i)['name'],
      for (int i = 0; i < 10000; i++)
        'number${i.toString().padLeft(5, '0')}': i,
    };

/// An array of 5000 small maps.
Map<String, Object?> array() => <String, Object?>{
      'items': <Object?>[for (int i = 0; i < 5000; i++) leaf(i)],
    };

/// Maps nested [depth] levels deep, each level with a few scalar fields.
Map<String, Object?> deep(int depth) {
  Map<String, Object?> value = <String, Object?>{'bottom': true};
  for (int i = depth; i > 0; i--) {
    value = <String, Object?>{'level': i, 'name': 'level $i', 'child': value};
  }
  return value;
}

/// About 1 MiB: 20 sections of 200 maps with a 200 character string each.
Map<String, Object?> large() => <String, Object?>{
      for (int s = 0; s < 20; s++)
        'section$s': <String, Object?>{
          for (int i = 0; i < 200; i++)
            'entry$i': <String, Object?>{
              'text': 'x' * 200,
              'n': i,
              'nested': leaf(i)
            },
        },
    };

final Map<String, Map<String, Object?> Function()> shapes =
    <String, Map<String, Object?> Function()>{
  'wide': wide,
  'array': array,
  'deep20': () => deep(20),
  'deep30': () => deep(30),
  'deep250': () => deep(250),
  'deep1000': () => deep(1000),
  'large': large,
};

double median(List<double> values) {
  values.sort();
  return values[values.length ~/ 2];
}

/// Runs [body] [reps] times (after one warm up run) and returns the median in milliseconds.
double time(int reps, void Function() body) {
  body();
  final List<double> samples = <double>[];
  for (int i = 0; i < reps; i++) {
    final Stopwatch watch = Stopwatch()..start();
    body();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  return median(samples);
}

void main(List<String> args) {
  int reps = 9;
  String? only;
  for (final String arg in args) {
    if (arg.startsWith('--reps=')) {
      reps = int.parse(arg.substring('--reps='.length));
    } else if (arg.startsWith('--only=')) {
      only = arg.substring('--only='.length);
    }
  }

  const List<String> steps = <String>[
    'parse',
    'encode',
    'toBytes',
    'fromBytes',
    'decode',
    'local',
    'read'
  ];
  print(
      '${'shape'.padRight(10)}${'KiB'.padLeft(8)}${steps.map((String s) => s.padLeft(10)).join()}');

  for (final MapEntry<String, Map<String, Object?> Function()> shape
      in shapes.entries) {
    if (only != null && shape.key != only) {
      continue;
    }
    final Map<String, Object?> input = shape.value();
    final Map<String, double> results = <String, double>{};

    late ObjectValue parsed;
    results['parse'] = time(reps, () {
      final UserDataParsedSetData data = reader.parseSetData(input);
      parsed =
          (data.toMutation(docKey, Precondition.none) as SetMutation).value;
    });

    late proto_v1.Value encoded;
    results['encode'] = time(reps, () => encoded = remote.encodeValue(parsed));

    late Uint8List bytes;
    results['toBytes'] = time(reps, () => bytes = encoded.writeToBuffer());

    final bool readsBytes = !shape.key.startsWith('deep') ||
        int.parse(shape.key.substring(4)) <= 30;
    proto_v1.Value fromBytes = encoded;
    if (readsBytes) {
      results['fromBytes'] =
          time(reps, () => fromBytes = proto_v1.Value.fromBuffer(bytes));
    }

    late FieldValue decoded;
    results['decode'] =
        time(reps, () => decoded = remote.decodeValue(fromBytes));
    if (decoded != parsed) {
      throw StateError(
          '${shape.key}: the decoded value differs from the parsed one');
    }

    final Document document = Document(
        docKey, SnapshotVersion(Timestamp(1, 0)), DocumentState.synced, parsed);
    if (readsBytes)
      results['local'] = time(reps, () {
        final Uint8List stored =
            local.encodeMaybeDocument(document).writeToBuffer();
        final MaybeDocument read =
            local.decodeMaybeDocument(proto.MaybeDocument.fromBuffer(stored));
        (read as Document).data;
      });

    final DocumentSnapshot<Map<String, Object?>> snapshot =
        DocumentSnapshotInternal.create<Map<String, Object?>>(
      firestore,
      docKey,
      document,
      isFromCache: false,
      hasPendingWrites: false,
    );
    results['read'] = time(reps, () => snapshot.data);

    print(
        '${shape.key.padRight(10)}${(bytes.length / 1024).toStringAsFixed(0).padLeft(8)}'
        '${steps.map((String s) => (results[s]?.toStringAsFixed(2) ?? '-').padLeft(10)).join()}');
  }
}
