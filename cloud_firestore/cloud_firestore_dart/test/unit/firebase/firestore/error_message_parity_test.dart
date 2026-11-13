// The argument validation messages that follow the JS SDK
// (packages/firestore/src/lite-api/user_data_reader.ts, reference.ts,
// util/input_validation.ts and test/integration/api/validation.test.ts).
// Dart names the method by its class (`DocumentReference.set` where JS has
// `setDoc`), and keeps its error types (ArgumentError where JS throws a
// FirestoreError with the code invalid-argument).

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart'
    show FirestoreInternal;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:test/test.dart';

class _Foo {}

Matcher throwsArgumentErrorWith(String message) => throwsA(
  isA<ArgumentError>().having(
    (ArgumentError e) => '${e.message}',
    'message',
    message,
  ),
);

void main() {
  final Firestore db = FirestoreInternal.detached(DatabaseId.forProject('p'));
  final Firestore otherDb = FirestoreInternal.detached(
    DatabaseId.forProject('q'),
  );
  final DocumentReference<Map<String, Object?>> doc = db.doc('c/d');
  final CollectionReference<Map<String, Object?>> coll = db.collection('c');

  group('write data', () {
    test('names the method, the field and the document', () async {
      final Map<String, Object?> data = <String, Object?>{
        'a': <String, Object?>{'b': _Foo()},
      };
      const String reason =
          'Unsupported field value: a custom _Foo object '
          '(found in field a.b in document c/d)';
      String error(String methodName) =>
          'Function $methodName() called with invalid data. $reason';

      await expectLater(
        () => doc.set(data),
        throwsArgumentErrorWith(error('DocumentReference.set')),
      );
      await expectLater(
        () => doc.set(data, SetOptions.mergeAllFields),
        throwsArgumentErrorWith(error('DocumentReference.set')),
      );
      await expectLater(
        () => doc.update(data),
        throwsArgumentErrorWith(error('DocumentReference.update')),
      );
      await expectLater(
        () => doc.updateFromList(<Object?>['a', data['a']]),
        throwsArgumentErrorWith(error('DocumentReference.updateFromList')),
      );
      expect(
        () => db.batch().set(doc, data),
        throwsArgumentErrorWith(error('WriteBatch.set')),
      );
      expect(
        () => db.batch().update(doc, data),
        throwsArgumentErrorWith(error('WriteBatch.update')),
      );
    });

    test('add() names CollectionReference.add', () async {
      await expectLater(
        () => coll.add(<String, Object?>{'a': _Foo()}),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            allOf(
              startsWith(
                'Function CollectionReference.add() called with invalid data. '
                'Unsupported field value: a custom _Foo object '
                '(found in field a in document c/',
              ),
              endsWith(')'),
            ),
          ),
        ),
      );
    });

    test('says when the data comes from a converter', () async {
      final DocumentReference<int> typed = doc.withConverter<int>(
        FirestoreDataConverter<int>.from(
          fromFirestore: (_, _) => 1,
          toFirestore: (int value, _) => <String, Object?>{'a': _Foo()},
        ),
      );
      await expectLater(
        () => typed.set(1),
        throwsArgumentErrorWith(
          'Function DocumentReference.set() called with invalid data '
          '(via `toFirestore()`). Unsupported field value: a custom _Foo '
          'object (found in field a in document c/d)',
        ),
      );
    });

    test('describes functions like the JS SDK', () async {
      await expectLater(
        () => doc.set(<String, Object?>{'f': () {}}),
        throwsArgumentErrorWith(
          'Function DocumentReference.set() called with invalid data. '
          'Unsupported field value: a function (found in field f in document '
          'c/d)',
        ),
      );
    });

    test('a reason without a field gets the document alone', () async {
      await expectLater(
        () => doc.set(<String, Object?>{
          'a': <Object?>[
            <int>[1],
          ],
        }),
        throwsArgumentErrorWith(
          'Function DocumentReference.set() called with invalid data. Nested '
          'arrays are not supported (found in document c/d)',
        ),
      );
    });

    test('array transform elements name the transform', () async {
      await expectLater(
        () => doc.update(<String, Object?>{
          'a': FieldValue.arrayUnion(<Object?>[_Foo()]),
        }),
        throwsArgumentErrorWith(
          'Function FieldValue.arrayUnion() called with invalid data. '
          'Unsupported field value: a custom _Foo object (found in document '
          'c/d)',
        ),
      );
    });

    test('references to another database', () async {
      await expectLater(
        () => doc.set(<String, Object?>{'r': otherDb.doc('c/d')}),
        throwsArgumentErrorWith(
          'Function DocumentReference.set() called with invalid data. '
          'Document reference is for database q/(default) but should be for '
          'database p/(default) (found in field r in document c/d)',
        ),
      );
    });

    test('a field mask path missing from the data', () async {
      await expectLater(
        () => doc.set(
          <String, Object?>{'a': 1},
          SetOptions.mergeFieldPaths(<FieldPath>[
            FieldPath.of(<String>['b']),
          ]),
        ),
        throwsArgumentErrorWith(
          "Field 'b' is specified in your field mask but missing from your "
          'input data.',
        ),
      );
    });

    test('update field paths name the method and the document', () async {
      await expectLater(
        () => doc.update(<String, Object?>{'a..b': 1}),
        throwsArgumentErrorWith(
          'Function DocumentReference.update() called with invalid data. '
          "Invalid field path (a..b). Paths must not be empty, begin with '.', "
          "end with '.', or contain '..' (found in document c/d)",
        ),
      );
    });

    test('updateFromList arguments', () async {
      await expectLater(
        () => doc.updateFromList(<Object?>['a']),
        throwsArgumentErrorWith(
          'Function DocumentReference.updateFromList() needs to be called with '
          'an even number of arguments that alternate between field names and '
          'values.',
        ),
      );
      await expectLater(
        () => doc.updateFromList(<Object?>[1, 2]),
        throwsArgumentErrorWith(
          'Function DocumentReference.updateFromList() called with invalid '
          'data. Expected a field name (a String or a FieldPath) at argument '
          'position 2, but got 1. The arguments should alternate between '
          'field names and values.',
        ),
      );
    });
  });

  group('query arguments', () {
    test('where values name where()', () {
      expect(
        () => coll.where('a', isEqualTo: _Foo()),
        throwsArgumentErrorWith(
          'Function where() called with invalid data. Unsupported field '
          'value: a custom _Foo object',
        ),
      );
      expect(
        () => coll.whereEqualTo('a', <String, Object?>{
          'b': FieldValue.increment(1),
        }),
        throwsArgumentErrorWith(
          'Function where() called with invalid data. FieldValue.increment() '
          'can only be used with set() and update() (found in field b)',
        ),
      );
    });

    test('cursor values name the cursor method', () {
      expect(
        () => coll.orderBy('a').startAfter(<Object?>[_Foo()]),
        throwsArgumentErrorWith(
          'Function startAfter() called with invalid data. Unsupported field '
          'value: a custom _Foo object',
        ),
      );
    });

    test('field paths name the method', () {
      const String reserved =
          'Invalid field path (a~b). Paths must not '
          "contain '~', '*', '/', '[', or ']'. Use FieldPath.of() for field "
          'names that contain them.';
      expect(
        () => coll.where('a~b', isEqualTo: 1),
        throwsArgumentErrorWith(
          'Function where() called with invalid data. $reserved',
        ),
      );
      expect(
        () => coll.whereLessThan('a~b', 1),
        throwsArgumentErrorWith(
          'Function where() called with invalid data. $reserved',
        ),
      );
      expect(
        () => coll.orderBy('a..b'),
        throwsArgumentErrorWith(
          'Function orderBy() called with invalid data. Invalid field path '
          "(a..b). Paths must not be empty, begin with '.', end with '.', or "
          "contain '..'",
        ),
      );
      expect(
        () => FieldPath.fromDotSeparatedPath('a~b'),
        throwsArgumentErrorWith(reserved),
      );
    });
  });

  group('paths', () {
    test('empty paths name the method', () {
      String empty(String methodName) =>
          'Function $methodName() cannot be called with an empty path.';
      expect(
        () => db.collection(''),
        throwsArgumentErrorWith(empty('Firestore.collection')),
      );
      expect(() => db.doc(''), throwsArgumentErrorWith(empty('Firestore.doc')));
      expect(
        () => doc.collection(''),
        throwsArgumentErrorWith(empty('DocumentReference.collection')),
      );
      expect(
        () => coll.doc(''),
        throwsArgumentErrorWith(empty('CollectionReference.doc')),
      );
    });

    test('collection group ids', () {
      expect(
        () => db.collectionGroup(''),
        throwsArgumentErrorWith(
          'Function Firestore.collectionGroup() cannot be called with an '
          'empty collectionId.',
        ),
      );
      expect(
        () => db.collectionGroup('a/b'),
        throwsArgumentErrorWith(
          "Invalid collection ID 'a/b' passed to function "
          "Firestore.collectionGroup(). Collection IDs must not contain '/'.",
        ),
      );
    });
  });
}
