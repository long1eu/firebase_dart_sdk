// The values that an encoding can easily get wrong, written by one client and read from the backend by another:
// the sign of zero, an empty Blob, NaN, the infinities and the bounds of 64 bit integers. They take a different path
// on each transport: binary protobuf over gRPC, proto3 JSON over the web transport (REST and WebChannel), where
// `toProto3Json()` of package:protobuf alone loses the sign of -0.0 and the type of an empty `bytesValue`.

import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart' show autoId;
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

typedef Json = Map<String, Object?>;

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/value_fidelity';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  // The JSON endpoints of the emulator (v1.22.0) read every usual spelling of a negative zero as 0.0: with curl,
  // `{"doubleValue": -0.0}`, `-0e0`, `"-0.0"` and `"-0"` (what the JS SDK sends, and this client) are all stored as
  // 0.0, while a document written over gRPC is returned as `-0.0` by the same endpoints. So the sign cannot be
  // written through the web transport there; the encoding itself is covered by the unit tests of the transport.
  final String? negativeZeroSkip =
      (Platform.environment['FIRESTORE_TEST_TRANSPORT'] ?? '')
              .startsWith('webchannel')
          ? 'The JSON endpoints of the emulator store -0.0 as 0.0, whatever its spelling'
          : null;

  final int maxInt = int.parse('9223372036854775807');
  final int minInt = int.parse('-9223372036854775808');

  /// Writes [data] with one client and reads it from the backend with another, so that nothing comes from a cache.
  Future<Json> throughBackend(Json data,
      {bool viaTransaction = false}) async {
    final Firestore writer = await IntegrationTestUtil.testFirestore();
    final Firestore reader = await IntegrationTestUtil.testFirestore();
    final DocumentReference<Json> doc =
        writer.collection('fidelity${autoId()}').doc('values');
    if (viaTransaction) {
      // Commit instead of the write stream (REST instead of WebChannel on the web transport).
      await writer.runTransaction<void>((Transaction transaction) async {
        transaction.set(doc, data);
      });
    } else {
      await doc.set(data);
    }
    final DocumentSnapshot<Json> snapshot =
        await reader.doc(doc.path).get(Source.server);
    expect(snapshot.metadata.isFromCache, isFalse);
    return snapshot.data!;
  }

  void expectNegativeZero(Object? value) {
    expect(value, isA<double>());
    expect(value, 0.0);
    expect((value! as double).isNegative, isTrue, reason: 'the sign of -0.0');
  }

  void expectPositiveZero(Object? value) {
    expect(value, isA<double>());
    expect(value, 0.0);
    expect((value! as double).isNegative, isFalse);
  }

  for (final bool viaTransaction in <bool>[false, true]) {
    final String how = viaTransaction ? 'a commit' : 'the write stream';

    test('doubles keep their special values through $how', () async {
      final Json read = await throughBackend(<String, Object?>{
        'positiveZero': 0.0,
        'nan': double.nan,
        'infinity': double.infinity,
        'negativeInfinity': double.negativeInfinity,
        'max': double.maxFinite,
        'min': double.minPositive,
        'nested': <String, Object?>{
          'list': <Object?>[0.0, 1.5, double.nan],
        },
      }, viaTransaction: viaTransaction);

      expectPositiveZero(read['positiveZero']);
      expect((read['nan']! as double).isNaN, isTrue);
      expect(read['infinity'], double.infinity);
      expect(read['negativeInfinity'], double.negativeInfinity);
      expect(read['max'], double.maxFinite);
      expect(read['min'], double.minPositive);
      final List<Object?> list =
          (read['nested']! as Json)['list']! as List<Object?>;
      expectPositiveZero(list[0]);
      expect(list[1], 1.5);
      expect((list[2]! as double).isNaN, isTrue);
    });

    test('a negative zero keeps its sign through $how', () async {
      final Json read = await throughBackend(<String, Object?>{
        'negativeZero': -0.0,
        'list': <Object?>[-0.0],
        'point': const GeoPoint(-0.0, -0.0),
      }, viaTransaction: viaTransaction);

      expectNegativeZero(read['negativeZero']);
      expectNegativeZero((read['list']! as List<Object?>).single);
      final GeoPoint point = read['point']! as GeoPoint;
      expectNegativeZero(point.latitude);
      expectNegativeZero(point.longitude);
    }, skip: negativeZeroSkip);

    test('an empty Blob stays a Blob through $how', () async {
      final Json read = await throughBackend(<String, Object?>{
        'empty': Blob(Uint8List(0)),
        'one': Blob(Uint8List.fromList(<int>[0])),
        'list': <Object?>[Blob(Uint8List(0))],
        'map': <String, Object?>{'empty': Blob(Uint8List(0))},
      }, viaTransaction: viaTransaction);

      expect(read['empty'], isA<Blob>());
      expect((read['empty']! as Blob).bytes, isEmpty);
      expect((read['one']! as Blob).bytes, <int>[0]);
      expect(((read['list']! as List<Object?>).single! as Blob).bytes, isEmpty);
      expect(((read['map']! as Json)['empty']! as Blob).bytes, isEmpty);
    });

    test('64 bit integers keep their bounds through $how', () async {
      final Json read = await throughBackend(<String, Object?>{
        'max': maxInt,
        'min': minInt,
        'zero': 0,
        'beyondDouble': int.parse('9007199254740993'),
      }, viaTransaction: viaTransaction);

      expect(read['max'], maxInt);
      expect(read['min'], minInt);
      expect(read['zero'], 0);
      expect(read['zero'], isA<int>());
      expect('${read['beyondDouble']}', '9007199254740993');
    });

    test('a GeoPoint keeps its coordinates through $how', () async {
      final Json read = await throughBackend(<String, Object?>{
        'zero': const GeoPoint(0, 0),
        'other': const GeoPoint(1.5, -2.5),
        'corner': const GeoPoint(-90, 180),
      }, viaTransaction: viaTransaction);

      expect(read['zero'], const GeoPoint(0, 0));
      expect(read['other'], const GeoPoint(1.5, -2.5));
      expect(read['corner'], const GeoPoint(-90, 180));
    });
  }

  test('these values work as query bounds and in transforms', () async {
    final Firestore firestore = await IntegrationTestUtil.testFirestore();
    final CollectionReference<Json> collection =
        firestore.collection('fidelity${autoId()}');
    await collection.doc('nan').set(<String, Object?>{'v': double.nan});
    await collection.doc('inf').set(<String, Object?>{'v': double.infinity});
    await collection.doc('zero').set(<String, Object?>{'v': -0.0});
    await collection.doc('blob').set(<String, Object?>{'v': Blob(Uint8List(0))});
    await collection.doc('max').set(<String, Object?>{'v': maxInt});

    Future<List<String>> ids(Query<Json> query) async =>
        (await query.get(Source.server))
            .docs
            .map((QueryDocumentSnapshot<Json> d) => d.id)
            .toList();

    expect(await ids(collection.where('v', isEqualTo: double.nan)),
        <String>['nan']);
    expect(await ids(collection.where('v', isEqualTo: double.infinity)),
        <String>['inf']);
    expect(await ids(collection.where('v', isEqualTo: Blob(Uint8List(0)))),
        <String>['blob']);
    expect(await ids(collection.where('v', isEqualTo: maxInt)), <String>['max']);
    // -0.0 and 0.0 are equal for queries.
    expect(await ids(collection.where('v', isEqualTo: 0.0)), <String>['zero']);

    // A transform with such an operand (an array of values in the request).
    await collection.doc('zero').update(<String, Object?>{
      'list': FieldValue.arrayUnion(<Object?>[1.5, Blob(Uint8List(0))]),
    });
    final List<Object?> list = (await collection.doc('zero').get(Source.server))
        .data!['list']! as List<Object?>;
    expect(list, hasLength(2));
    expect(list[0], 1.5);
    expect((list[1]! as Blob).bytes, isEmpty);
  });
}
