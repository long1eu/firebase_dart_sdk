import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_configuration.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// The parsing half of IndexingTest of the Android SDK (testCanConfigureIndexes,
/// testBadJsonDoesNotCrashClient, testBadIndexDoesNotCrashClient) and of
/// index_configuration tests of the JS SDK.
void main() {
  test('testCanConfigureIndexes', () {
    final List<FieldIndex> indexes = parseIndexConfiguration('''
{
  "indexes": [
    {
      "collectionGroup": "restaurants",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "price",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "avgRating",
          "order": "DESCENDING"
        }
      ]
    },
    {
      "collectionGroup": "restaurants",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "price",
          "order": "ASCENDING"
        }      ]
    }
  ],
  "fieldOverrides": []
}''');

    expect(indexes, <FieldIndex>[
      FieldIndex(
          FieldIndex.unknownId,
          'restaurants',
          <IndexSegment>[
            IndexSegment(field('price'), SegmentKind.ascending),
            IndexSegment(field('avgRating'), SegmentKind.descending),
          ],
          FieldIndex.initialState),
      FieldIndex(
          FieldIndex.unknownId,
          'restaurants',
          <IndexSegment>[IndexSegment(field('price'), SegmentKind.ascending)],
          FieldIndex.initialState),
    ]);
  });

  test('testBadJsonDoesNotCrashClient', () {
    expect(() => parseIndexConfiguration('{,'), throwsArgumentError);
  });

  test('testBadIndexDoesNotCrashClient', () {
    expect(() => parseIndexConfiguration('''
{
  "indexes": [
    {
      "collectionGroup": "restaurants",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "price",
          "order": "INVALID"
        ,
      ]
    }
  ],
  "fieldOverrides": []
}'''), throwsArgumentError);
  });

  test('array config, nested field paths and the default order', () {
    final List<FieldIndex> indexes = parseIndexConfiguration('''
{"indexes": [{"collectionGroup": "c", "fields": [
  {"fieldPath": "tags", "arrayConfig": "CONTAINS"},
  {"fieldPath": "a.b", "order": "ASCENDING"},
  {"fieldPath": "`with.dot`", "order": "DESCENDING"},
  {"fieldPath": "other", "order": "INVALID"},
  {"fieldPath": "bare"}
]}]}''');

    expect(indexes.single.segments, <IndexSegment>[
      IndexSegment(field('tags'), SegmentKind.contains),
      IndexSegment(field('a.b'), SegmentKind.ascending),
      IndexSegment(
          FieldPath.fromSegments(<String>['with.dot']), SegmentKind.descending),
      // Like Android: a field that is neither CONTAINS nor ASCENDING is
      // descending.
      IndexSegment(field('other'), SegmentKind.descending),
      IndexSegment(field('bare'), SegmentKind.descending),
    ]);
  });

  test('a configuration without indexes or fields', () {
    expect(parseIndexConfiguration('{}'), isEmpty);
    expect(parseIndexConfiguration('{"fieldOverrides": []}'), isEmpty);
    final List<FieldIndex> indexes =
        parseIndexConfiguration('{"indexes": [{"collectionGroup": "c"}]}');
    expect(indexes.single.collectionGroup, 'c');
    expect(indexes.single.segments, isEmpty);
  });

  test('rejects a configuration of the wrong shape', () {
    expect(() => parseIndexConfiguration('[]'), throwsArgumentError);
    expect(
        () => parseIndexConfiguration('{"indexes": {}}'), throwsArgumentError);
    expect(() => parseIndexConfiguration('{"indexes": [{}]}'),
        throwsArgumentError);
    expect(
        () => parseIndexConfiguration(
            '{"indexes": [{"collectionGroup": "c", "fields": [{}]}]}'),
        throwsArgumentError);
    expect(
        () => parseIndexConfiguration(
            '{"indexes": [{"collectionGroup": "c", "fields": [{"fieldPath": ""}]}]}'),
        throwsArgumentError);
  });

  test('accepts a decoded configuration', () {
    final List<FieldIndex> indexes =
        parseIndexConfigurationMap(<String, Object?>{
      'indexes': <Object?>[
        <String, Object?>{
          'collectionGroup': 'c',
          'fields': <Object?>[
            <String, Object?>{'fieldPath': 'a', 'order': 'ASCENDING'}
          ]
        }
      ]
    });
    expect(indexes.single.segments.single,
        IndexSegment(field('a'), SegmentKind.ascending));
  });
}
