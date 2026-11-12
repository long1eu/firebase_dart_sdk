// toJson()/fromJson() of snapshots and the bundles they carry, with BSON
// values in the documents and in the filters of the query.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' hide FieldValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;

class _TestFirestore extends Mock implements Firestore {
  _TestFirestore(this.databaseId);

  @override
  final DatabaseId databaseId;
}

final Firestore firestore = _TestFirestore(DatabaseId.forProject('project'));

Map<String, Object?> allTypes() {
  return <String, Object?>{
    'minKey': MinKey.instance,
    'maxKey': MaxKey.instance,
    'int32': Int32Value(-7),
    'decimal128': Decimal128Value('1.000000000000000000000000000000001'),
    'decimalNaN': Decimal128Value('NaN'),
    'oid': BsonObjectId('507f191e810c19729de860ea'),
    'timestamp': BsonTimestamp(4294967295, 2),
    'regex': const RegexValue('^foo', 'i'),
    'binary': Blob.bsonBinary(128, Uint8List.fromList(<int>[1, 2, 3])),
    'emptyBinary': Blob.bsonBinary(255, Uint8List(0)),
    'nested': <String, Object?>{
      'array': <Object?>[Int32Value(1), MaxKey.instance],
    },
    // Maps that only look like a BSON value stay maps.
    'notInt32': <String, Object?>{'__int__': 'a'},
    'notMinKey': <String, Object?>{'__min__': null, 'other': 1},
  };
}

QuerySnapshot<Map<String, Object?>> querySnapshot(
    core.Query query, List<Document> docs) {
  DocumentSet documents = DocumentSet.emptySet(query.comparator);
  for (final Document doc in docs) {
    documents = documents.add(doc);
  }
  final ViewSnapshot snapshot = ViewSnapshot.fromInitialDocuments(
    query,
    documents,
    DocumentKey.emptyKeySet,
    isFromCache: false,
    excludesMetadataChanges: false,
    hasCachedResults: false,
    readTime: SnapshotVersion.none,
  );
  return QuerySnapshot<Map<String, Object?>>(
      Query<Map<String, Object?>>(query, firestore), snapshot, firestore);
}

Future<List<BundleElement>> readBundle(String bundle) async {
  final BundleReader reader = BundleReader.fromBytes(
      BundleSerializer(RemoteSerializer(firestore.databaseId)),
      utf8.encode(bundle));
  final List<BundleElement> elements = <BundleElement>[
    await reader.getBundleMetadata()
  ];
  BundleElement? element;
  while ((element = await reader.getNextElement()) != null) {
    elements.add(element!);
  }
  return elements;
}

void main() {
  test('DocumentSnapshot.fromJson round-trips the BSON types', () async {
    final Document document = util.doc('coll/doc', 1000, allTypes());
    final DocumentSnapshot<Map<String, Object?>> snapshot =
        DocumentSnapshot<Map<String, Object?>>.fromDocument(firestore, document,
            isFromCache: true, hasPendingWrites: false);
    final Map<String, Object?> json =
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>;

    final DocumentSnapshot<Map<String, Object?>> fromJson =
        DocumentSnapshot<Map<String, Object?>>.fromJson(firestore, json);
    expect(fromJson.document!.data, document.data);
    expect(fromJson.data, allTypes());
    expect(fromJson.getInt32Value('int32'), Int32Value(-7));
    expect(fromJson.getDecimal128Value('decimal128')!.stringValue,
        '1.000000000000000000000000000000001');
    expect(fromJson.getBlob('binary')!.subtype, 128);
    expect(fromJson.get('notInt32'), <String, Object?>{'__int__': 'a'});

    // The bundle of the snapshot is what loadBundle() reads.
    final List<BundleElement> elements =
        await readBundle(json['bundle']! as String);
    final BundleDocument bundled = elements.whereType<BundleDocument>().single;
    expect(bundled.document.data, document.data);
  });

  test('QuerySnapshot.fromJson round-trips BSON documents and filters',
      () async {
    final core.Query query =
        util.query('coll').filter(util.andFilters(<core.Filter>[
              util.filter('key', '>=', Int32Value(1)),
              util.filter('key', '<', Decimal128Value('2.5')),
              util.filter('tag', 'in', <Object>[
                MinKey.instance,
                BsonObjectId('507f191e810c19729de860ea'),
                const RegexValue('^a', 'i'),
                BsonTimestamp(1, 2),
                Blob.bsonBinary(5, Uint8List.fromList(<int>[1])),
              ]),
            ]));
    final List<Document> docs = <Document>[
      util.doc('coll/a', 1000, <String, Object?>{
        'key': Int32Value(1),
        'tag': MinKey.instance,
        ...allTypes(),
      }),
      util.doc('coll/b', 2000, <String, Object?>{
        'key': Decimal128Value('2.25'),
        'tag': const RegexValue('^a', 'i'),
      }),
      util.doc('coll/c', 3000,
          <String, Object?>{'key': 2, 'tag': BsonTimestamp(1, 2)}),
    ];
    for (final Document doc in docs) {
      expect(query.matches(doc), isTrue, reason: '${doc.key}');
    }

    final Map<String, Object?> json =
        jsonDecode(jsonEncode(querySnapshot(query, docs).toJson()))
            as Map<String, Object?>;
    final QuerySnapshot<Map<String, Object?>> fromJson =
        QuerySnapshot<Map<String, Object?>>.fromJson(firestore, json);
    // The numbers sort by value: Int32 1 < int 2 < Decimal128 2.25.
    expect(
        fromJson.docs
            .map((DocumentSnapshot<Map<String, Object?>> d) => d.id)
            .toList(),
        <String>['a', 'c', 'b']);
    for (final Document doc in docs) {
      expect(
          fromJson.docs
              .firstWhere((DocumentSnapshot<Map<String, Object?>> d) =>
                  d.id == doc.key.path.last)
              .document!
              .data,
          doc.data);
    }

    final List<BundleElement> elements =
        await readBundle(json['bundle']! as String);
    final NamedQuery namedQuery = elements.whereType<NamedQuery>().single;
    expect(namedQuery.bundledQuery,
        BundledQuery(query, BundledQueryLimitType.first));
    expect(
        elements
            .whereType<BundleDocument>()
            .map((BundleDocument d) => d.document.data)
            .toList(),
        unorderedEquals(docs.map((Document d) => d.data).toList()));
  });

  test('the JSON of the value classes round-trips', () {
    final Blob binary = Blob.bsonBinary(7, Uint8List.fromList(<int>[1, 2]));
    final Blob decoded = Blob.fromJson(
        jsonDecode(jsonEncode(binary.toJson())) as Map<String, Object?>);
    expect(decoded, binary);
    expect(decoded.subtype, 7);
    expect(util.wrap(decoded), isA<BlobValue>());
  });
}
