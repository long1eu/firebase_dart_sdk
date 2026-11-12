// Property: every serializer reads back what it wrote.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as api;
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/proto3_json.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';

import '../../util/property.dart';
import '../../util/property_model.dart';

final RemoteSerializer remote = RemoteSerializer(modelDatabaseId);
final LocalSerializer local = LocalSerializer(remote);
final BundleSerializer bundle = BundleSerializer(remote);

/// [value] and [other] are equal and sort together, and so do their parts
/// (`==` of numbers tells 0.0 from -0.0 and an integer from a double).
void expectSameValue(FieldValue other, FieldValue value) {
  expect(other, value);
  expect(other.compareTo(value), 0);
  expect(other.runtimeType, value.runtimeType);
}

/// Sends [message] through the binary encoding and through proto3 JSON as the
/// web transport writes it ([toFirestoreProto3Json]: `toProto3Json()` alone
/// loses a negative zero and an empty `bytesValue`, see the group
/// "proto3 JSON") and expects the same bytes.
void expectProtoRoundTrips<T extends GeneratedMessage>(
  T message,
  T Function() create,
) {
  final Uint8List bytes = message.writeToBuffer();
  final T fromBinary = create()..mergeFromBuffer(bytes);
  // Compared as bytes: a message with a NaN is not equal to itself.
  expect(fromBinary.writeToBuffer(), bytes, reason: 'binary round trip');

  final Object? json = jsonDecode(jsonEncode(toFirestoreProto3Json(message)));
  final T fromJson = create()..mergeFromProto3Json(json);
  expect(
    fromJson.writeToBuffer(),
    bytes,
    reason: 'proto3 JSON round trip of $json',
  );
}

void main() {
  group('RemoteSerializer', () {
    test('values', () {
      forAll<FieldValue>(
        'remote value',
        count: cases(600),
        generate: (Gen gen) => gen.modelValue(),
        show: (FieldValue value) => value.toString(),
        check: (FieldValue value) {
          final pb.Value encoded = remote.encodeValue(value);
          expectSameValue(remote.decodeValue(encoded), value);
          expectProtoRoundTrips(encoded, pb.Value.create);
        },
      );
    });

    test('documents', () {
      forAll<Document>(
        'remote document',
        count: cases(300),
        generate: (Gen gen) => gen.document(),
        show: (Document doc) => '${doc.key} ${doc.data}',
        check: (Document doc) {
          final proto.Document encoded = remote.encodeDocument(
            doc.key,
            doc.data,
          );
          expect(remote.decodeKey(encoded.name), doc.key);
          expectSameValue(
            remote.decodeDocumentFields(encoded.fields),
            doc.data,
          );
          expectProtoRoundTrips(encoded, proto.Document.create);
        },
      );
    });

    test('mutations', () {
      forAll<Mutation>(
        'remote mutation',
        count: cases(600),
        generate: (Gen gen) => gen.mutation(),
        show: (Mutation mutation) => mutation.toString(),
        check: (Mutation mutation) {
          final proto.Write encoded = remote.encodeMutation(mutation);
          expect(remote.decodeMutation(encoded), mutation);
          expectProtoRoundTrips(encoded, proto.Write.create);
        },
      );
    });

    test('query targets', () {
      forAll<Query>(
        'remote target',
        count: cases(600),
        generate: (Gen gen) => gen.query(),
        show: (Query query) => query.toTarget().canonicalId,
        check: (Query query) {
          final Target target = query.toTarget();
          if (target.isDocumentQuery) {
            final proto.Target_DocumentsTarget encoded = remote
                .encodeDocumentsTarget(target);
            expect(remote.decodeDocumentsTarget(encoded), target);
            return;
          }
          final proto.Target_QueryTarget encoded = remote.encodeQueryTarget(
            target,
          );
          final Target decoded = remote.decodeQueryTarget(encoded);
          expect(decoded, target);
          expect(decoded.canonicalId, target.canonicalId);
          expectProtoRoundTrips(encoded, proto.Target_QueryTarget.create);
        },
      );
    });

    test('document targets', () {
      forAll<DocumentKey>(
        'remote documents target',
        count: cases(50),
        generate: (Gen gen) => gen.documentKey(),
        check: (DocumentKey key) {
          final Target target = Query(key.path).toTarget();
          expect(
            remote.decodeDocumentsTarget(remote.encodeDocumentsTarget(target)),
            target,
          );
        },
      );
    });
  });

  group('LocalSerializer', () {
    test('documents', () {
      forAll<MaybeDocument>(
        'local document',
        count: cases(400),
        generate: (Gen gen) => gen.maybeDocument(),
        show: (MaybeDocument doc) => doc.toString(),
        check: (MaybeDocument doc) {
          final proto.MaybeDocument encoded = local.encodeMaybeDocument(doc);
          final MaybeDocument decoded = local.decodeMaybeDocument(
            proto.MaybeDocument.fromBuffer(encoded.writeToBuffer()),
          );
          expect(decoded, doc);
          expect(decoded.runtimeType, doc.runtimeType);
          if (doc is Document) {
            expectSameValue((decoded as Document).data, doc.data);
          }
        },
      );
    });

    test('mutation batches', () {
      forAll<MutationBatch>(
        'local mutation batch',
        count: cases(300),
        generate: (Gen gen) => MutationBatch(
          batchId: gen.between(1, 100000),
          localWriteTime: gen.timestamp(),
          baseMutations: <Mutation>[
            for (int i = gen.below(3); i > 0; i--) gen.mutation(),
          ],
          mutations: <Mutation>[
            for (int i = gen.between(1, 4); i > 0; i--) gen.mutation(),
          ],
        ),
        show: (MutationBatch batch) => batch.toString(),
        check: (MutationBatch batch) {
          final proto.WriteBatch encoded = local.encodeMutationBatch(batch);
          final MutationBatch decoded = local.decodeMutationBatch(
            proto.WriteBatch.fromBuffer(encoded.writeToBuffer()),
          );
          expect(decoded, batch);
          expect(decoded.mutations, batch.mutations);
          expect(decoded.baseMutations, batch.baseMutations);
        },
      );
    });

    test('overlay mutations', () {
      forAll<Mutation>(
        'local overlay mutation',
        count: cases(400),
        generate: (Gen gen) => gen.mutation(),
        show: (Mutation mutation) => mutation.toString(),
        check: (Mutation mutation) {
          final proto.Write encoded = local.encodeOverlayMutation(mutation);
          expect(
            local.decodeOverlayMutation(
              proto.Write.fromBuffer(encoded.writeToBuffer()),
            ),
            mutation,
          );
        },
      );
    });

    test('targets', () {
      forAll<QueryData>(
        'local target',
        count: cases(400),
        generate: (Gen gen) => QueryData(
          gen.query().toTarget(),
          gen.between(1, 100000),
          gen.between(0, 1 << 40),
          QueryPurpose.listen,
          gen.snapshotVersion(),
          gen.bytes(),
          null,
          gen.chance(50) ? gen.snapshotVersion() : null,
        ),
        show: (QueryData data) => data.toString(),
        check: (QueryData data) {
          final proto.Target encoded = local.encodeQueryData(data);
          final QueryData decoded = local.decodeQueryData(
            proto.Target.fromBuffer(encoded.writeToBuffer()),
          );
          expect(decoded, data);
          expect(decoded.target, data.target);
        },
      );
    });
  });

  // The generators never build a composite filter of one filter, because
  // the serializers read it back as that one filter. This shows that the
  // public API does not build one either, so that a stored target is found
  // again.
  test('Filter.or / Filter.and of a single filter round-trip', () {
    for (final api.Filter filter in <api.Filter>[
      api.Filter.or(<api.Filter>[api.Filter.equalTo('a', 1)]),
      api.Filter.and(<api.Filter>[api.Filter.equalTo('a', 1)]),
      api.Filter.or(<api.Filter>[
        api.Filter.and(<api.Filter>[api.Filter.greaterThan('a', 1)]),
      ]),
      api.Filter.and(<api.Filter>[
        api.Filter.or(<api.Filter>[api.Filter.equalTo('a', 1)]),
        api.Filter.equalTo('b', 2),
      ]),
    ]) {
      final Target target = api.Query<Map<String, Object?>>(
        Query(ResourcePath.fromString('coll')),
        modelFirestore,
      ).where(filter).query.toTarget();
      final Target decoded = remote.decodeQueryTarget(
        remote.encodeQueryTarget(target),
      );
      expect(decoded, target, reason: '$filter');
      expect(decoded.canonicalId, target.canonicalId, reason: '$filter');
    }
  });

  group('BundleSerializer', () {
    test('reads the proto3 JSON of a value', () {
      forAll<FieldValue>(
        'bundle value',
        count: cases(600),
        generate: (Gen gen) => gen.modelValue(),
        show: (FieldValue value) => value.toString(),
        check: (FieldValue value) {
          final Object? json = jsonDecode(
            jsonEncode(toFirestoreProto3Json(remote.encodeValue(value))),
          );
          expectSameValue(
            bundle.decodeValue(json! as Map<String, dynamic>),
            value,
          );
        },
      );
    });

    test('reads the proto3 JSON of a document', () {
      forAll<Document>(
        'bundle document',
        count: cases(300),
        generate: (Gen gen) => gen.document(),
        show: (Document doc) => '${doc.key} ${doc.data}',
        check: (Document doc) {
          final proto.Document encoded =
              remote.encodeDocument(doc.key, doc.data).deepCopy()
                ..updateTime = remote.encodeVersion(doc.version);
          final Object? json = jsonDecode(
            jsonEncode(toFirestoreProto3Json(encoded)),
          );
          final Document decoded = bundle
              .decodeDocument(json! as Map<String, dynamic>)
              .document;
          expect(decoded.key, doc.key);
          expect(decoded.version, doc.version);
          expectSameValue(decoded.data, doc.data);
        },
      );
    });
  });

  // What `toProto3Json()` of package:protobuf loses. The bundle builder
  // writes values itself for this reason, and so does the web transport
  // (`toFirestoreProto3Json`).
  group('proto3 JSON', () {
    test('quirk: a negative zero is written as 0', () {
      final pb.Value value = pb.Value()..doubleValue = -0.0;
      expect(jsonEncode(value.toProto3Json()), '{"doubleValue":0}');
      final pb.Value decoded = pb.Value()
        ..mergeFromProto3Json(jsonDecode(jsonEncode(value.toProto3Json())));
      expect(decoded.doubleValue.isNegative, isFalse);
    });

    test('quirk: an empty bytes value loses its type', () {
      final pb.Value value = pb.Value()..bytesValue = <int>[];
      expect(value.whichValueType(), pb.Value_ValueType.bytesValue);
      final String json = jsonEncode(value.toProto3Json());
      final pb.Value decoded = pb.Value()
        ..mergeFromProto3Json(jsonDecode(json));
      expect(
        decoded.writeToBuffer(),
        isNot(value.writeToBuffer()),
        reason:
            'fixed in package:protobuf? Then toFirestoreProto3Json can go. '
            'JSON: $json',
      );
    });

    test('the encoder of the web transport writes both faithfully', () {
      for (final pb.Value value in <pb.Value>[
        pb.Value()..doubleValue = -0.0,
        pb.Value()..bytesValue = <int>[],
      ]) {
        final String json = jsonEncode(toFirestoreProto3Json(value));
        final pb.Value decoded = pb.Value()
          ..mergeFromProto3Json(jsonDecode(json));
        expect(decoded.writeToBuffer(), value.writeToBuffer(), reason: json);
        expect(decoded.whichValueType(), value.whichValueType());
      }
      expect(
        (pb.Value()..mergeFromProto3Json(
              jsonDecode(
                jsonEncode(
                  toFirestoreProto3Json(pb.Value()..doubleValue = -0.0),
                ),
              ),
            ))
            .doubleValue
            .isNegative,
        isTrue,
      );
    });
  });

  group('snapshot JSON', () {
    api.DocumentSnapshot<Map<String, Object?>> snapshotOf(Document document) =>
        api.DocumentSnapshot<Map<String, Object?>>.fromDocument(
          modelFirestore,
          document,
          isFromCache: false,
          hasPendingWrites: false,
        );

    test('document snapshots', () {
      forAll<Document>(
        'document snapshot JSON',
        count: cases(300),
        generate: (Gen gen) => Document(
          gen.documentKey(),
          gen.snapshotVersion(),
          DocumentState.synced,
          gen.objectValue(),
        ),
        show: (Document doc) => '${doc.key} ${doc.data}',
        check: (Document doc) {
          final Map<String, Object?> json =
              jsonDecode(jsonEncode(snapshotOf(doc).toJson()))
                  as Map<String, Object?>;
          final api.DocumentSnapshot<Map<String, Object?>> decoded =
              api.DocumentSnapshot<Map<String, Object?>>.fromJson(
                modelFirestore,
                json,
              );
          expect(decoded.reference.path, doc.key.path.canonicalString);
          expectSameValue(decoded.document!.data, doc.data);
          expect(decoded.document!.version, doc.version);
        },
      );
    });

    test('query snapshots', () {
      forAll<List<Object>>(
        'query snapshot JSON',
        count: cases(150),
        generate: (Gen gen) {
          // A query without bounds and filters on generated documents of
          // one collection, so that every document belongs to the result.
          Query query = Query(
            ResourcePath.fromString(
              gen.pick(const <String>['coll', 'coll/a/sub']),
            ),
          );
          // The snapshot keeps whatever documents it is given, so the
          // filters do not have to match them.
          for (int i = gen.below(3); i > 0; i--) {
            query = query.filter(gen.filter());
          }
          if (gen.chance(30)) {
            query = query.limitToFirst(gen.between(5, 20));
          }
          final Map<DocumentKey, Document> docs = <DocumentKey, Document>{};
          for (int i = gen.below(5); i > 0; i--) {
            final DocumentKey key = DocumentKey.fromPath(
              query.path.appendSegment(
                gen.pick(const <String>['a', 'b', 'c', 'é']),
              ),
            );
            // A result document has every field the query orders by.
            ObjectValue data = gen.objectValue();
            final List<FieldPath> ordered = <FieldPath>[
              for (final OrderBy order in query.orderByConstraints)
                if (!order.field.isKeyField) order.field,
            ]..sort((FieldPath a, FieldPath b) => a.length.compareTo(b.length));
            for (final FieldPath path in ordered) {
              if (data.get(path) == null) {
                data = data.set(path, toModel(gen.integer()));
              }
            }
            docs[key] = Document(
              key,
              gen.snapshotVersion(),
              DocumentState.synced,
              data,
            );
          }
          return <Object>[query, docs.values.toList()];
        },
        show: (List<Object> value) =>
            '${(value[0] as Query).canonicalId} with ${(value[1] as List<Document>).map((Document d) => '${d.key} ${d.data}').join('; ')}',
        check: (List<Object> value) {
          final Query query = value[0] as Query;
          DocumentSet documents = DocumentSet.emptySet(query.comparator);
          for (final Document doc in value[1] as List<Document>) {
            documents = documents.add(doc);
          }
          final api.QuerySnapshot<Map<String, Object?>> snapshot =
              api.QuerySnapshot<Map<String, Object?>>(
                api.Query<Map<String, Object?>>(query, modelFirestore),
                ViewSnapshot.fromInitialDocuments(
                  query,
                  documents,
                  DocumentKey.emptyKeySet,
                  isFromCache: false,
                  excludesMetadataChanges: false,
                  hasCachedResults: false,
                  readTime: SnapshotVersion.none,
                ),
                modelFirestore,
              );
          final Map<String, Object?> json =
              jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>;
          final api.QuerySnapshot<Map<String, Object?>> decoded =
              api.QuerySnapshot<Map<String, Object?>>.fromJson(
                modelFirestore,
                json,
              );
          expect(decoded.query.query, query);
          expect(decoded.docs.length, documents.length);
          for (int i = 0; i < decoded.docs.length; i++) {
            final Document expected = documents.toList()[i];
            expect(decoded.docs[i].document!.key, expected.key);
            expectSameValue(decoded.docs[i].document!.data, expected.data);
          }
        },
      );
    });
  });
}
