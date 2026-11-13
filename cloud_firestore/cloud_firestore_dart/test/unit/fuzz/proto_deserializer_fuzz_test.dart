// Fuzz: the protobuf to model deserializers (RemoteSerializer for what the
// backend sends, LocalSerializer for what the cache holds) on malformed input.
//
// Valid protos round-trip (test/unit/property/serializer_property_test.dart).
// Here every decoder gets hostile protos, built field by field and mutated
// byte by byte. It must either return a model object that behaves (compares
// with itself, re-encodes to the same model, converts to user data) or reject
// the input cleanly (see isCleanRejection in test/util/fuzz.dart); never
// crash with a TypeError, a RangeError or a stack overflow, and never hang.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart'
    show DocumentSnapshotInternal;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';

import '../../util/fuzz.dart';
import '../../util/property.dart';
import '../../util/property_model.dart';

final RemoteSerializer remote = RemoteSerializer(modelDatabaseId);
final LocalSerializer local = LocalSerializer(remote);

const String root = 'projects/project/databases/(default)/documents';

/// Resource names a hostile backend or a corrupt cache could hold.
const List<String> hostileNames = <String>[
  '',
  '/',
  '//',
  'projects',
  'projects/project',
  'projects/project/databases',
  'projects/project/databases/(default)',
  root,
  '$root/',
  '$root/c',
  '$root/c/d',
  '$root/c/d/e',
  '$root/c/d/e/f',
  '$root//d',
  '$root/c//',
  'projects/other/databases/(default)/documents/c/d',
  'projects/project/databases/other/documents/c/d',
  'projects/project/databases/(default)/nope/c/d',
  'x/project/y/(default)/documents/c/d',
  '$root/c/__id1__',
  '$root/c/d/../e',
  '$root/c/é',
  'projects/p/databases/d/documents/c/d',
  'projects//databases//',
];

extension HostileProtos on Gen {
  Int64 int64() => Int64(integer());

  proto.Timestamp hostileTimestamp() => proto.Timestamp()
    ..seconds = chance(50)
        ? Int64(
            pick(const <int>[
              0, -1, 1, -62135596800, -62135596801, 253402300799, //
              253402300800, 9223372036854775807, -9223372036854775808,
            ]),
          )
        : Int64(integer())
    ..nanos = chance(50)
        ? pick(const <int>[0, 1, -1, 999999999, 1000000000, 2147483647])
        : between(-2147483648, 2147483647);

  String hostileName() => chance(70) ? pick(hostileNames) : string();

  /// A Value with any (or no) value type, with hostile contents.
  pb.Value hostileValue([int depth = 3]) {
    final pb.Value value = pb.Value();
    switch (below(depth > 0 ? 15 : 12)) {
      case 0:
        // No value type at all.
        break;
      case 1:
        value.nullValue = proto.NullValue.NULL_VALUE;
        break;
      case 2:
        value.booleanValue = chance(50);
        break;
      case 3:
        value.integerValue = int64();
        break;
      case 4:
        value.doubleValue = float();
        break;
      case 5:
        value.timestampValue = hostileTimestamp();
        break;
      case 6:
        value.stringValue = string();
        break;
      case 7:
        value.bytesValue = bytes();
        break;
      case 8:
        value.referenceValue = hostileName();
        break;
      case 9:
        value.geoPointValue = proto.LatLng()
          ..latitude = chance(50) ? float() : between(-90, 90).toDouble()
          ..longitude = chance(50) ? float() : between(-180, 180).toDouble();
        break;
      case 10:
        value.mapValue = specialMap(depth);
        break;
      case 11:
        // An unknown field: what a newer backend could send.
        value.unknownFields.mergeVarintField(between(20, 100), int64());
        break;
      case 12:
        value.arrayValue = proto.ArrayValue()
          ..values.addAll(<pb.Value>[
            for (int i = below(4); i > 0; i--) hostileValue(depth - 1),
          ]);
        break;
      default:
        value.mapValue = proto.MapValue()
          ..fields.addAll(<String, pb.Value>{
            for (int i = below(4); i > 0; i--)
              hostileKey(): hostileValue(depth - 1),
          });
    }
    return value;
  }

  String hostileKey() => chance(60)
      ? pick(const <String>[
          'a', '', '__type__', 'value', '__min__', '__max__', '__int__', //
          '__decimal128__', '__oid__', '__binary__', '__request_timestamp__',
          '__regex__', 'seconds', 'increment', 'pattern', 'options',
          '__previous_value__', '__local_write_time__', 'a.b', '`',
        ])
      : string();

  /// A map shaped like one of the special maps (vector, BSON values, server
  /// timestamps), with hostile contents.
  proto.MapValue specialMap(int depth) {
    pb.Value scalar() => hostileValue(0);
    final pb.Value inner;
    switch (below(5)) {
      case 0:
        return proto.MapValue()
          ..fields['__type__'] = (pb.Value()
            ..stringValue = pick(const <String>[
              '__vector__',
              'server_timestamp',
              '',
            ]))
          ..fields['value'] = (pb.Value()
            ..arrayValue = (proto.ArrayValue()
              ..values.addAll(<pb.Value>[
                for (int i = below(4); i > 0; i--) scalar(),
              ])));
      case 1:
        inner = pb.Value()
          ..mapValue = (proto.MapValue()
            ..fields['seconds'] = scalar()
            ..fields['increment'] = scalar());
        return proto.MapValue()..fields['__request_timestamp__'] = inner;
      case 2:
        inner = pb.Value()
          ..mapValue = (proto.MapValue()
            ..fields['pattern'] = scalar()
            ..fields['options'] = scalar());
        return proto.MapValue()..fields['__regex__'] = inner;
      case 3:
        return proto.MapValue()
          ..fields[pick(const <String>[
            '__min__', '__max__', '__int__', '__decimal128__', '__oid__', //
            '__binary__',
          ])] = chance(50)
              ? scalar()
              : (pb.Value()
                  ..stringValue = pick(const <String>[
                    '', 'NaN', '-0', '1e999999', '1e-999999', '0x10', '1_0', //
                    'zz', '507f1f77bcf86cd799439011', '1.', '.1', '+1', '--1',
                    'Infinity',
                    'inf',
                    '1e',
                    '99999999999999999999999999999999999999999',
                  ]));
      default:
        return proto.MapValue()
          ..fields['__type__'] = (pb.Value()..stringValue = 'server_timestamp')
          ..fields['__local_write_time__'] = (pb.Value()
            ..timestampValue = hostileTimestamp())
          ..fields['__previous_value__'] = hostileValue(depth - 1);
    }
  }

  pb.Document hostileDocument() => pb.Document()
    ..name = chance(60)
        ? '$root/c/${pick(const <String>['d', 'e'])}'
        : hostileName()
    ..fields.addAll(<String, pb.Value>{
      for (int i = below(4); i > 0; i--) hostileKey(): hostileValue(),
    })
    ..updateTime = hostileTimestamp()
    ..createTime = hostileTimestamp();

  pb.ListenResponse hostileListenResponse() {
    final pb.ListenResponse response = pb.ListenResponse();
    switch (below(6)) {
      case 0:
        response.targetChange = pb.TargetChange()
          ..targetChangeType = pick(pb.TargetChange_TargetChangeType.values)
          ..targetIds.addAll(<int>[
            for (int i = below(3); i > 0; i--) integer().toSigned(32),
          ])
          ..resumeToken = bytes()
          ..readTime = hostileTimestamp()
          ..cause = (proto.Status()
            ..code = chance(50) ? between(0, 16) : integer().toSigned(32)
            ..message = string());
        break;
      case 1:
        response.documentChange = pb.DocumentChange()
          ..document = hostileDocument()
          ..targetIds.add(between(-2, 5))
          ..removedTargetIds.add(between(-2, 5));
        break;
      case 2:
        response.documentDelete = pb.DocumentDelete()
          ..document = hostileName()
          ..readTime = hostileTimestamp();
        break;
      case 3:
        response.documentRemove = pb.DocumentRemove()..document = hostileName();
        break;
      case 4:
        response.filter = pb.ExistenceFilter()
          ..targetId = integer().toSigned(32)
          ..count = integer().toSigned(32)
          ..unchangedNames = (pb.BloomFilter()
            ..hashCount = integer().toSigned(32)
            ..bits = (pb.BitSequence()
              ..bitmap = bytes()
              ..padding = integer().toSigned(32)));
        break;
      default:
        // Nothing set.
        break;
    }
    return response;
  }

  pb.BatchGetDocumentsResponse hostileBatchGetResponse() {
    final pb.BatchGetDocumentsResponse response = pb.BatchGetDocumentsResponse()
      ..readTime = hostileTimestamp();
    switch (below(3)) {
      case 0:
        response.found = hostileDocument();
        break;
      case 1:
        response.missing = hostileName();
        break;
      default:
        break;
    }
    return response;
  }

  pb.Write hostileWrite() {
    final pb.Write write = pb.Write();
    switch (below(4)) {
      case 0:
        write.update = hostileDocument();
        if (chance(50)) {
          write.updateMask = pb.DocumentMask()
            ..fieldPaths.addAll(<String>[
              for (int i = below(3); i > 0; i--) hostileFieldPath(),
            ]);
        }
        break;
      case 1:
        write.delete = hostileName();
        break;
      case 2:
        write.verify = hostileName();
        break;
      default:
        break;
    }
    for (int i = below(3); i > 0; i--) {
      final pb.DocumentTransform_FieldTransform transform =
          pb.DocumentTransform_FieldTransform()..fieldPath = hostileFieldPath();
      switch (below(7)) {
        case 0:
          transform.setToServerValue = pick(
            pb.DocumentTransform_FieldTransform_ServerValue.values,
          );
          break;
        case 1:
          transform.increment = hostileValue(1);
          break;
        case 2:
          transform.maximum = hostileValue(1);
          break;
        case 3:
          transform.minimum = hostileValue(1);
          break;
        case 4:
          transform.appendMissingElements = proto.ArrayValue()
            ..values.add(hostileValue(1));
          break;
        case 5:
          transform.removeAllFromArray = proto.ArrayValue()
            ..values.add(hostileValue(1));
          break;
        default:
          break;
      }
      write.updateTransforms.add(transform);
    }
    if (chance(30)) {
      write.currentDocument = chance(50)
          ? (pb.Precondition()..updateTime = hostileTimestamp())
          : (pb.Precondition()..exists = chance(50));
    }
    return write;
  }

  String hostileFieldPath() => chance(50)
      ? pick(const <String>[
          'a', 'a.b', '', '.', 'a.', '.a', '`', '``', '`a', 'a`', '`a.b`', //
          '`\\`', '\\', 'a..b', '__name__', '`a`.`b`', '`a\\`',
        ])
      : string();

  /// A Target_QueryTarget with hostile filters, orders and cursors.
  pb.Target_QueryTarget hostileQueryTarget([int depth = 3]) {
    final pb.StructuredQuery query = pb.StructuredQuery();
    for (int i = below(3); i > 0; i--) {
      query.from.add(
        pb.StructuredQuery_CollectionSelector()
          ..collectionId = chance(70) ? 'c' : string()
          ..allDescendants = chance(30),
      );
    }
    if (chance(70)) {
      query.where = hostileFilter(depth);
    }
    for (int i = below(3); i > 0; i--) {
      query.orderBy.add(
        pb.StructuredQuery_Order()
          ..field_1 = (pb.StructuredQuery_FieldReference()
            ..fieldPath = hostileFieldPath())
          ..direction = pick(pb.StructuredQuery_Direction.values),
      );
    }
    if (chance(30)) {
      query.startAt = pb.Cursor()
        ..values.addAll(<pb.Value>[
          for (int i = below(3); i > 0; i--) hostileValue(1),
        ])
        ..before = chance(50);
    }
    if (chance(30)) {
      query.endAt = pb.Cursor()
        ..values.addAll(<pb.Value>[
          for (int i = below(3); i > 0; i--) hostileValue(1),
        ])
        ..before = chance(50);
    }
    if (chance(30)) {
      query.limit = proto.Int32Value()..value = integer().toSigned(32);
    }
    return pb.Target_QueryTarget()
      ..parent = chance(60) ? root : hostileName()
      ..structuredQuery = query;
  }

  pb.StructuredQuery_Filter hostileFilter(int depth) {
    final pb.StructuredQuery_Filter filter = pb.StructuredQuery_Filter();
    switch (below(depth > 0 ? 4 : 3)) {
      case 0:
        filter.fieldFilter = pb.StructuredQuery_FieldFilter()
          ..field_1 = (pb.StructuredQuery_FieldReference()
            ..fieldPath = hostileFieldPath())
          ..op = pick(pb.StructuredQuery_FieldFilter_Operator.values)
          ..value = hostileValue(1);
        break;
      case 1:
        filter.unaryFilter = pb.StructuredQuery_UnaryFilter()
          ..field_2 = (pb.StructuredQuery_FieldReference()
            ..fieldPath = hostileFieldPath())
          ..op = pick(pb.StructuredQuery_UnaryFilter_Operator.values);
        break;
      case 2:
        break;
      default:
        filter.compositeFilter = pb.StructuredQuery_CompositeFilter()
          ..op = pick(pb.StructuredQuery_CompositeFilter_Operator.values)
          ..filters.addAll(<pb.StructuredQuery_Filter>[
            for (int i = below(4); i > 0; i--) hostileFilter(depth - 1),
          ]);
    }
    return filter;
  }
}

/// A decoded value must behave like any other value. The fields of a
/// [document] are not a map value: a document whose only field is `__max__`
/// is not a MaxKey.
void expectWellBehaved(FieldValue value, {bool document = false}) {
  expect(value.compareTo(value), 0);
  expect(value == value, isTrue);
  expect(value.hashCode, value.hashCode);
  value.toString();
  final FieldValue again = document
      ? remote.decodeDocumentFields(remote.encodeValue(value).mapValue.fields)
      : remote.decodeValue(remote.encodeValue(value));
  expect(again.compareTo(value), 0, reason: 'a decoded value re-encodes');
  expect(again, value);
}

/// A decoded document must convert to user data, or reject its malformed
/// fields cleanly when they are read: a document from the backend decodes its
/// fields lazily, as upstream keeps them as protos and converts them when the
/// user reads them.
void expectReadable(MaybeDocument document) {
  if (document is! Document) {
    document.toString();
    return;
  }
  final ObjectValue? data = acceptOrReject(
    () => document.data,
    () => '${document.key} ${document.proto}',
  );
  if (data == null) {
    return;
  }
  document.toString();
  expectWellBehaved(data, document: true);
  final Object? user =
      DocumentSnapshotInternal.fromDocument<Map<String, Object?>>(
        modelFirestore,
        document,
        isFromCache: false,
        hasPendingWrites: false,
      ).data;
  expect(user, isA<Map<String, Object?>>());
}

/// Runs [check] on [count] hostile messages from [generate], each also sent
/// through the binary encoding with a few bytes mutated.
void fuzzMessage<T extends GeneratedMessage>(
  String name, {
  required int count,
  required T Function(Gen gen) generate,
  required T Function(List<int> bytes) parse,
  required void Function(T message) check,
}) {
  forAll<(T, T?)>(
    name,
    count: count,
    generate: (Gen gen) {
      final T message = generate(gen);
      final Uint8List mutated = gen.mutateBytes(message.writeToBuffer());
      T? parsed;
      try {
        parsed = parse(mutated);
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        // The protobuf package rejects bytes it cannot parse; for some it
        // throws a RangeError instead of an InvalidProtocolBufferException
        // (protobuf 6.1.0, a string length past the end). Either way the
        // deserializers never see such a message.
        parsed = null;
      }
      return (message, parsed);
    },
    show: ((T, T?) messages) => '${messages.$1}\nmutated: ${messages.$2}',
    check: ((T, T?) messages) {
      for (final T? message in <T?>[messages.$1, messages.$2]) {
        if (message != null) {
          check(message);
        }
      }
    },
  );
}

void main() {
  group('RemoteSerializer', () {
    test('decodeValue of hostile values', () {
      fuzzMessage<pb.Value>(
        'hostile value',
        count: cases(2000),
        generate: (Gen gen) => gen.hostileValue(),
        parse: pb.Value.fromBuffer,
        check: (pb.Value message) {
          final FieldValue? value = acceptOrReject(
            () => remote.decodeValue(message),
            () => '$message',
          );
          if (value != null) {
            expectWellBehaved(value);
          }
        },
      );
    });

    test('decodeWatchChange of hostile listen responses', () {
      fuzzMessage<pb.ListenResponse>(
        'hostile listen response',
        count: cases(1500),
        generate: (Gen gen) => gen.hostileListenResponse(),
        parse: pb.ListenResponse.fromBuffer,
        check: (pb.ListenResponse message) {
          final WatchChange? change = acceptOrReject(() {
            remote.decodeVersionFromListenResponse(message);
            return remote.decodeWatchChange(message);
          }, () => '$message');
          if (change is WatchChangeDocumentChange) {
            final MaybeDocument? document = change.newDocument;
            if (document != null) {
              expectReadable(document);
            }
          }
        },
      );
    });

    test('decodeMaybeDocument of hostile batch get responses', () {
      fuzzMessage<pb.BatchGetDocumentsResponse>(
        'hostile batch get response',
        count: cases(1500),
        generate: (Gen gen) => gen.hostileBatchGetResponse(),
        parse: pb.BatchGetDocumentsResponse.fromBuffer,
        check: (pb.BatchGetDocumentsResponse message) {
          final MaybeDocument? document = acceptOrReject(
            () => remote.decodeMaybeDocument(message),
            () => '$message',
          );
          if (document != null) {
            expectReadable(document);
          }
        },
      );
    });

    test('decodeQueryTarget of hostile queries', () {
      fuzzMessage<pb.Target_QueryTarget>(
        'hostile query target',
        count: cases(1500),
        generate: (Gen gen) => gen.hostileQueryTarget(),
        parse: pb.Target_QueryTarget.fromBuffer,
        check: (pb.Target_QueryTarget message) {
          final Target? target = acceptOrReject(
            () => remote.decodeQueryTarget(message),
            () => '$message',
          );
          if (target != null) {
            expect(target.canonicalId, isA<String>());
            expect(target, target);
          }
        },
      );
    });

    test('decodeMutation of hostile writes', () {
      fuzzMessage<pb.Write>(
        'hostile write',
        count: cases(1500),
        generate: (Gen gen) => gen.hostileWrite(),
        parse: pb.Write.fromBuffer,
        check: (pb.Write message) {
          final Mutation? mutation = acceptOrReject(
            () => remote.decodeMutation(message),
            () => '$message',
          );
          mutation?.toString();
        },
      );
    });

    test('values nested deeper than the binary decoder allows', () {
      // The binary decoder stops at 64 levels; a message built in memory (or
      // read from proto3 JSON) can be deeper.
      for (final int depth in <int>[100, 1000]) {
        pb.Value value = pb.Value()..integerValue = Int64(1);
        for (int i = 0; i < depth; i++) {
          value = i.isEven
              ? (pb.Value()
                  ..arrayValue = (proto.ArrayValue()..values.add(value)))
              : (pb.Value()
                  ..mapValue = (proto.MapValue()..fields['a'] = value));
        }
        acceptOrReject(() => remote.decodeValue(value), () => 'depth $depth');
      }
    });
  });

  group('LocalSerializer', () {
    test('decodeMaybeDocument of hostile cache entries', () {
      fuzzMessage<proto.MaybeDocument>(
        'hostile cached document',
        count: cases(1500),
        generate: (Gen gen) {
          final proto.MaybeDocument document = proto.MaybeDocument()
            ..hasCommittedMutations = gen.chance(30);
          switch (gen.below(4)) {
            case 0:
              document.document = gen.hostileDocument();
              break;
            case 1:
              document.noDocument = proto.NoDocument()
                ..name = gen.hostileName()
                ..readTime = gen.hostileTimestamp();
              break;
            case 2:
              document.unknownDocument = proto.UnknownDocument()
                ..name = gen.hostileName()
                ..version = gen.hostileTimestamp();
              break;
            default:
              break;
          }
          return document;
        },
        parse: proto.MaybeDocument.fromBuffer,
        check: (proto.MaybeDocument message) {
          final MaybeDocument? document = acceptOrReject(
            () => local.decodeMaybeDocument(message),
            () => '$message',
          );
          if (document != null) {
            expectReadable(document);
          }
        },
      );
    });

    test('decodeMutationBatch of hostile batches', () {
      fuzzMessage<proto.WriteBatch>(
        'hostile mutation batch',
        count: cases(800),
        generate: (Gen gen) => proto.WriteBatch()
          ..batchId = gen.integer().toSigned(32)
          ..localWriteTime = gen.hostileTimestamp()
          ..writes.addAll(<pb.Write>[
            for (int i = gen.below(3); i > 0; i--) gen.hostileWrite(),
          ])
          ..baseWrites.addAll(<pb.Write>[
            for (int i = gen.below(2); i > 0; i--) gen.hostileWrite(),
          ]),
        parse: proto.WriteBatch.fromBuffer,
        check: (proto.WriteBatch message) {
          acceptOrReject(
            () => local.decodeMutationBatch(message),
            () => '$message',
          )?.toString();
        },
      );
    });

    test('decodeQueryData of hostile targets', () {
      fuzzMessage<proto.Target>(
        'hostile target',
        count: cases(800),
        generate: (Gen gen) {
          final proto.Target target = proto.Target()
            ..targetId = gen.integer().toSigned(32)
            ..snapshotVersion = gen.hostileTimestamp()
            ..lastLimboFreeSnapshotVersion = gen.hostileTimestamp()
            ..resumeToken = gen.bytes()
            ..lastListenSequenceNumber = gen.int64();
          if (gen.chance(70)) {
            target.query = gen.hostileQueryTarget();
          } else if (gen.chance(80)) {
            target.documents = pb.Target_DocumentsTarget()
              ..documents.addAll(<String>[
                for (int i = gen.below(3); i > 0; i--) gen.hostileName(),
              ]);
          }
          return target;
        },
        parse: proto.Target.fromBuffer,
        check: (proto.Target message) {
          acceptOrReject(
            () => local.decodeQueryData(message),
            () => '$message',
          )?.toString();
        },
      );
    });
  });
}
