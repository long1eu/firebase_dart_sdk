// Plain maps that have the encoded shape of a BSON value, for example
// `{'__int__': 5}`. On the wire such a map and an `Int32Value` are the same.
//
// Document data can not contain them: field names that begin and end with `__`
// are rejected when the data is parsed, so a pending write never holds one and
// nothing can change when the write is read back from the mutation queue
// after a restart. Query values are not checked like that, there the map is
// read as the BSON value, like the backend does.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' hide FieldValue;
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as api
    show FieldValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';

void main() {
  final DatabaseId databaseId = DatabaseId.forProject('project');
  final UserDataConverter converter = UserDataConverter(databaseId);
  final RemoteSerializer remoteSerializer = RemoteSerializer(databaseId);
  final LocalSerializer serializer = LocalSerializer(remoteSerializer);
  final Timestamp writeTime = Timestamp.now();

  final Map<String, Map<String, Object?>> shapes =
      <String, Map<String, Object?>>{
    'int32': <String, Object?>{'__int__': 5},
    'decimal128': <String, Object?>{'__decimal128__': '1.5'},
    'minKey': <String, Object?>{'__min__': null},
    'maxKey': <String, Object?>{'__max__': null},
    'objectId': <String, Object?>{'__oid__': '507f191e810c19729de860ea'},
    'timestamp': <String, Object?>{
      '__request_timestamp__': <String, Object?>{'seconds': 1, 'increment': 2}
    },
    'regex': <String, Object?>{
      '__regex__': <String, Object?>{'pattern': '^a', 'options': 'i'}
    },
    'binary': <String, Object?>{
      '__binary__': Blob(Uint8List.fromList(<int>[7, 1, 2]))
    },
  };

  final Map<String, Object> values = <String, Object>{
    'int32': Int32Value(5),
    'decimal128': Decimal128Value('1.5'),
    'minKey': MinKey.instance,
    'maxKey': MaxKey.instance,
    'objectId': BsonObjectId('507f191e810c19729de860ea'),
    'timestamp': BsonTimestamp(1, 2),
    'regex': const RegexValue('^a', 'i'),
    'binary': Blob.bsonBinary(7, Uint8List.fromList(<int>[1, 2])),
  };

  final Matcher throwsReservedField = throwsA(isA<ArgumentError>().having(
      (ArgumentError e) => '${e.message}',
      'message',
      contains('Document fields cannot begin and end with "__"')));

  group('document data rejects a plain map shaped like', () {
    for (final MapEntry<String, Map<String, Object?>> shape in shapes.entries) {
      test(shape.key, () {
        final Map<String, Object?> data = <String, Object?>{'a': shape.value};
        expect(() => converter.parseSetData(data), throwsReservedField);
        expect(() => converter.parseMergeData(data, null), throwsReservedField);
        expect(() => converter.parseMergeData(data, fieldMask(<String>['a'])),
            throwsReservedField);
        expect(() => converter.parseUpdateData(data), throwsReservedField);
        expect(
            () => converter.parseUpdateData(
                <String, Object?>{'a.${shape.value.keys.single}': 1}),
            throwsReservedField);
        // Nested in a map and in an array.
        expect(
            () => converter.parseSetData(<String, Object?>{
                  'm': <String, Object?>{'a': shape.value}
                }),
            throwsReservedField);
        expect(
            () => converter.parseSetData(<String, Object?>{
                  'l': <Object?>[shape.value]
                }),
            throwsReservedField);
      });
    }
  });

  group('a pending merge write of', () {
    /// What a restart does to a pending write: it is written to and read from
    /// the mutation queue.
    Mutation restart(Mutation mutation) {
      final MutationBatch batch = MutationBatch(
          batchId: 1,
          localWriteTime: writeTime,
          baseMutations: <Mutation>[],
          mutations: <Mutation>[mutation]);
      return serializer
          .decodeMutationBatch(serializer.encodeMutationBatch(batch))
          .mutations
          .single;
    }

    ObjectValue? localView(Mutation mutation, Document? base) {
      final MaybeDocument? result =
          mutation.applyToLocalView(base, base, writeTime);
      return result is Document ? result.data : null;
    }

    final Map<String, Document?> bases = <String, Document?>{
      'a missing document': null,
      'a document without the field':
          doc('docs/1', 1, <String, Object?>{'b': 2}),
      'a document with a map in the field': doc('docs/1', 1, <String, Object?>{
        'a': <String, Object?>{'x': 1},
        'b': 2
      }),
      'a document with a BSON value in the field':
          doc('docs/1', 1, <String, Object?>{'a': Int32Value(7), 'b': 2}),
    };

    for (final MapEntry<String, Object> value in values.entries) {
      for (final MapEntry<String, Document?> base in bases.entries) {
        test('${value.key} into ${base.key} is the same after a restart', () {
          final Map<String, Object?> data = <String, Object?>{
            'a': value.value,
            'n': <String, Object?>{'deep': value.value},
          };
          for (final Mutation mutation in <Mutation>[
            converter
                .parseMergeData(data, null)
                .toMutation(key('docs/1'), Precondition.none),
            converter
                .parseMergeData(data, fieldMask(<String>['a', 'n.deep']))
                .toMutation(key('docs/1'), Precondition.none),
            converter
                .parseSetData(data)
                .toMutation(key('docs/1'), Precondition.none),
            if (base.value != null)
              converter.parseUpdateData(<String, Object?>{
                'a': value.value,
                'n.deep': value.value
              }).toMutation(key('docs/1'), Precondition(exists: true)),
          ]) {
            final Mutation restarted = restart(mutation);
            expect(restarted, mutation);
            expect(remoteSerializer.encodeMutation(restarted),
                remoteSerializer.encodeMutation(mutation));

            final ObjectValue? before = localView(mutation, base.value);
            final ObjectValue? after = localView(restarted, base.value);
            expect(before, isNotNull);
            expect(after, before);
            expect(before!.get(field('a')), wrap(value.value));
            expect(before.get(field('n.deep')), wrap(value.value));
            expect(after!.get(field('a'))!.runtimeType,
                wrap(value.value).runtimeType);
          }
        });
      }
    }
  });

  group('an array transform element that is a plain map shaped like', () {
    for (final MapEntry<String, Map<String, Object?>> shape in shapes.entries) {
      test('${shape.key} is that BSON value, also after a restart', () {
        for (final api.FieldValue Function(List<Object?>) transform
            in <api.FieldValue Function(List<Object?>)>[
          api.FieldValue.arrayUnion,
          api.FieldValue.arrayRemove,
        ]) {
          final Mutation mutation = converter.parseUpdateData(<String, Object?>{
            'l': transform(<Object?>[shape.value, 1])
          }).toMutation(key('docs/1'), Precondition(exists: true));
          final Mutation typed = converter.parseUpdateData(<String, Object?>{
            'l': transform(<Object?>[values[shape.key], 1])
          }).toMutation(key('docs/1'), Precondition(exists: true));
          expect(mutation, typed);

          final MutationBatch batch = MutationBatch(
              batchId: 1,
              localWriteTime: writeTime,
              baseMutations: <Mutation>[],
              mutations: <Mutation>[mutation]);
          final Mutation restarted = serializer
              .decodeMutationBatch(serializer.encodeMutationBatch(batch))
              .mutations
              .single;
          expect(restarted, mutation);

          final Document base = doc('docs/1', 1, <String, Object?>{
            'l': <Object?>[values[shape.key], 2]
          });
          expect(
              (restarted.applyToLocalView(base, base, writeTime)! as Document)
                  .data,
              (mutation.applyToLocalView(base, base, writeTime)! as Document)
                  .data);
        }
      });
    }

    test('adds nothing the array already holds as the BSON value', () {
      final Document base = doc('docs/1', 1, <String, Object?>{
        'l': <Object?>[Int32Value(5)]
      });
      final Mutation mutation = converter.parseUpdateData(<String, Object?>{
        'l': api.FieldValue.arrayUnion(<Object?>[
          <String, Object?>{'__int__': 5}
        ])
      }).toMutation(key('docs/1'), Precondition(exists: true));
      expect(
          (mutation.applyToLocalView(base, base, writeTime)! as Document)
              .data
              .value,
          <String, Object?>{
            'l': <Object?>[Int32Value(5)]
          });
    });
  });

  group('a query value that is a plain map shaped like', () {
    for (final MapEntry<String, Map<String, Object?>> shape in shapes.entries) {
      test('${shape.key} is that BSON value', () {
        final FieldValue expected = wrap(values[shape.key]);
        final FieldValue parsed = converter.parseQueryValue(shape.value);
        expect(parsed, expected);
        expect(parsed.runtimeType, expected.runtimeType);
        expect(remoteSerializer.encodeValue(parsed),
            remoteSerializer.encodeValue(expected));

        // In an array (the operand of `in`) and nested in a map.
        expect(
            converter
                .parseQueryValue(<Object?>[shape.value, 1], allowArrays: true),
            wrap(<Object?>[values[shape.key], 1]));
        expect(
            converter.parseQueryValue(<String, Object?>{
              'a': <Object?>[shape.value]
            }),
            wrap(<String, Object?>{
              'a': <Object?>[values[shape.key]]
            }));

        // The filter matches the documents the backend returns for it.
        expect(
            filter('v', '==', shape.value).matches(
                doc('docs/1', 1, <String, Object?>{'v': values[shape.key]})),
            isTrue);
      });
    }

    test('nothing else is left as a map', () {
      for (final Map<String, Object?> map in <Map<String, Object?>>[
        <String, Object?>{'__int__': 'a'},
        <String, Object?>{'__int__': 2147483648},
        <String, Object?>{'__int__': 1, 'other': 2},
        <String, Object?>{'__min__': 1},
        <String, Object?>{'__decimal128__': 'abc'},
        <String, Object?>{
          '__binary__': Blob(Uint8List.fromList(<int>[0, 1]))
        },
        <String, Object?>{'__binary__': Blob(Uint8List(0))},
        <String, Object?>{
          '__request_timestamp__': <String, Object?>{
            'seconds': -1,
            'increment': 2
          }
        },
        <String, Object?>{
          '__regex__': <String, Object?>{'pattern': 'a'}
        },
        <String, Object?>{'__unknown__': 1},
        <String, Object?>{'a': 1},
      ]) {
        final FieldValue parsed = converter.parseQueryValue(map);
        expect(parsed, isA<ObjectValue>(), reason: '$map');
        expect(parsed.value, map);
      }
    });
  });
}
