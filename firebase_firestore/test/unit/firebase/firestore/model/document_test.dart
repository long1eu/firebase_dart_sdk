// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  test('testConstructor', () {
    final Document document = Document(key('messages/first'), version(1),
        wrapList(<dynamic>['a', 1]), DocumentState.SYNCED);

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
        Document(key('rooms/eros'), version(1), data, DocumentState.SYNCED);

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
    expect(doc(key1, 1, data1, DocumentState.LOCAL_MUTATIONS) == doc1, isFalse);
  });
}

// ignore: always_specify_types
const doc = TestUtil.doc;
// ignore: always_specify_types
const key = TestUtil.key;
// ignore: always_specify_types
const version = TestUtil.version;
// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const field = TestUtil.field;
// ignore: always_specify_types
const wrapList = TestUtil.wrapList;
