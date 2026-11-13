// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show
        Blob,
        BsonObjectId,
        BsonTimestamp,
        Decimal128Value,
        Int32Value,
        MaxKey,
        MinKey,
        RegexValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  test('testInstantiation', () {
    final Document document = Document(key('messages/first'), version(1),
        DocumentState.synced, wrapList(<dynamic>['a', 1]));

    expect(document.key, key('messages/first'));
    expect(document.version, version(1));
    expect(document.data, wrapList(<dynamic>['a', 1]));
    expect(document.hasLocalMutations, isFalse);
  });

  test('testExtractFields', () {
    final ObjectValue data = wrapList(<Object>[
      'desc',
      'Discuss all the project related stuff',
      'owner',
      map<String>(<String>['name', 'Jonny', 'title', 'scallywag'])
    ]);
    final Document document =
        Document(key('rooms/eros'), version(1), DocumentState.synced, data);

    expect(document.getFieldValue(field('desc')),
        'Discuss all the project related stuff');
    expect(document.getFieldValue(field('owner.title')), 'scallywag');
  });

  test('testIsEqual', () {
    const String key1 = 'messages/first';
    const String key2 = 'messages/second';
    final Map<String, Object> data1 = map(<dynamic>['a', 1]);
    final Map<String, Object> data2 = map(<dynamic>['a', 2]);
    final Document doc1 = doc(key1, 1, data1);
    final Document doc2 = doc(key1, 1, data1);

    expect(doc2, doc1);
    expect(doc('messages/first', 1, map(<dynamic>['a', 1])), doc1);

    expect(doc(key1, 1, data2) == doc1, isFalse);
    expect(doc(key2, 1, data1) == doc1, isFalse);
    expect(doc(key1, 2, data1) == doc1, isFalse);
    expect(doc(key1, 1, data1, DocumentState.localMutations) == doc1, isFalse);
  });

  // Ported from the JS SDK's test/unit/model/document.test.ts.

  test('can be constructed with bson types', () {
    Map<String, Object> data() => <String, Object>{
      'objectId': const BsonObjectId('foo'),
      'binary': Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
      'timestamp': BsonTimestamp(1, 2),
      'min': MinKey.instance,
      'max': MaxKey.instance,
      'regex': const RegexValue('a', 'b'),
      'int32': Int32Value(1),
      'decimal128': Decimal128Value('1.2e3'),
    };
    final Document document = doc('rooms/Eros', 1, data());

    expect(document.data, wrapMap(data()));
    expect(document.hasLocalMutations, isFalse);
  });

  test('equals to other same documents', () {
    expect(doc('a/b', 0, <String, Object>{}) == Object(), isFalse);

    expect(
      doc('a/b', 3, <String, Object>{'foo': 'bar'}),
      doc('a/b', 3, <String, Object>{'foo': 'bar'}),
    );
    expect(
      doc('a/b', 1, <String, Object>{'foo': double.nan}),
      doc('a/b', 1, <String, Object>{'foo': double.nan}),
    );

    expect(
      doc('a/b', 1, <String, Object>{'foo': 'bar'}),
      isNot(doc('a/0', 1, <String, Object>{'foo': 'bar'})),
    );
    expect(
      doc('a/b', 1, <String, Object>{'foo': 'bar'}),
      isNot(doc('a/b', 2, <String, Object>{'foo': 'bar'})),
    );
    expect(
      doc('a/b', 1, <String, Object>{'foo': 'bar'}),
      isNot(doc('a/b', 1, <String, Object>{'foo': 100})),
    );
    expect(
      doc('a/b', 1, <String, Object>{
        'foo': 'bar',
      }, DocumentState.localMutations),
      isNot(doc('a/b', 1, <String, Object>{'foo': 'bar'})),
    );
  });
}
