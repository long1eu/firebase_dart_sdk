// Ported from the JS SDK:
// packages/firestore/test/unit/lite-api/types.test.ts
//
// The JS tests check the TypeScript compiler: their bodies are functions that
// are never called. The Dart port does the same, so what is tested is that
// this file compiles (the analyzer checks the types of the never-called
// functions). Only the "compiles" cases of the FirestoreTypeConverter suite
// have a Dart equivalent:
// - the "fails to compile" cases need `@ts-expect-error`, which Dart has no
//   counterpart of;
// - the UpdateData suites and the FirestoreDataConverter<T, U> case test the
//   typing of the update data and of a separate DbModelType, while Dart's
//   `update` takes a `Map<String, Object?>` and its converter has a single
//   type parameter.

import 'package:cloud_firestore_dart/lite.dart';
import 'package:test/test.dart';

class MyModelType {
  const MyModelType(this.stringProperty, this.numberProperty);

  final String stringProperty;
  final num numberProperty;
}

/// A converter declared with an explicit type, as
/// `const converter: FirestoreDataConverter<MyModelType> = {...}`.
class _ExplicitConverter extends FirestoreDataConverter<MyModelType> {
  const _ExplicitConverter();

  @override
  Map<String, Object?> toFirestore(MyModelType obj, SetOptions? options) =>
      <String, Object?>{'a': obj.stringProperty, 'b': obj.numberProperty};

  @override
  MyModelType fromFirestore(
    QueryDocumentSnapshot<Map<String, Object?>> snapshot,
  ) => MyModelType(snapshot.data['a']! as String, snapshot.data['b']! as num);
}

/// The JS test body shared by the converter cases.
Future<void> _useConverter(
  DocumentReference<Map<String, Object?>> docRef,
  FirestoreDataConverter<MyModelType> converter,
) async {
  final DocumentReference<MyModelType> newDocRef = docRef.withConverter(
    converter,
  );
  await newDocRef.set(const MyModelType('foo', 42));
  await newDocRef.update(<String, Object?>{'a': 'newFoo', 'b': 43});
  final DocumentSnapshot<MyModelType> snapshot = await newDocRef.get();
  final MyModelType data = snapshot.data!;
  expect(data.stringProperty, 'newFoo');
  expect(data.numberProperty, 43);
}

/// JS's `neverCall()`: keeps [body] for the analyzer without running it.
void neverCall<T>(T Function(DocumentReference<Map<String, Object?>>) body) {}

void main() {
  group('FirestoreTypeConverter', () {
    test('converter has the minimal typing information', () {
      // The parameter and return types of the functions are inferred.
      final FirestoreDataConverter<MyModelType> converter =
          FirestoreDataConverter<MyModelType>.from(
            toFirestore: (MyModelType obj, _) => <String, Object?>{
              'a': obj.stringProperty,
              'b': obj.numberProperty,
            },
            fromFirestore:
                (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
                    MyModelType(
                      snapshot.data['a']! as String,
                      snapshot.data['b']! as num,
                    ),
          );
      neverCall((DocumentReference<Map<String, Object?>> docRef) {
        return _useConverter(docRef, converter);
      });
    });

    test('converter has the minimal typing information plus return types', () {
      final FirestoreDataConverter<MyModelType> converter =
          FirestoreDataConverter<MyModelType>.from(
            toFirestore: (MyModelType obj, SetOptions? options) {
              return <String, Object?>{
                'a': obj.stringProperty,
                'b': obj.numberProperty,
              };
            },
            fromFirestore:
                (QueryDocumentSnapshot<Map<String, Object?>> snapshot) {
                  return MyModelType(
                    snapshot.data['a']! as String,
                    snapshot.data['b']! as num,
                  );
                },
          );
      neverCall((DocumentReference<Map<String, Object?>> docRef) {
        return _useConverter(docRef, converter);
      });
    });

    // JS's merge overload of toFirestore() is the SetOptions parameter here.
    test("has the additional 'merge' version of toFirestore()", () {
      final FirestoreDataConverter<MyModelType> converter =
          FirestoreDataConverter<MyModelType>.from(
            toFirestore: (MyModelType modelObject, SetOptions? options) {
              if (options == null) {
                return <String, Object?>{
                  'a': modelObject.stringProperty,
                  'b': modelObject.numberProperty,
                };
              }
              return <String, Object?>{'a': modelObject.stringProperty};
            },
            fromFirestore:
                (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
                    MyModelType(
                      snapshot.data['a']! as String,
                      snapshot.data['b']! as num,
                    ),
          );
      neverCall((DocumentReference<Map<String, Object?>> docRef) {
        return _useConverter(docRef, converter);
      });
    });

    test('converter is explicitly typed as FirestoreDataConverter<T>', () {
      const FirestoreDataConverter<MyModelType> converter =
          _ExplicitConverter();
      neverCall((DocumentReference<Map<String, Object?>> docRef) {
        return _useConverter(docRef, converter);
      });
    });

    test('updateDoc() successfully compiles even if DbModelType argument is '
        'missing properties', () {
      neverCall((DocumentReference<Map<String, Object?>> docRef) async {
        final DocumentReference<MyModelType> docRefWithConverter = docRef
            .withConverter(const _ExplicitConverter());
        await docRefWithConverter.update(<String, Object?>{});
      });
    });

    test('getDoc() returns AppModelType', () {
      neverCall<Future<MyModelType>>((
        DocumentReference<Map<String, Object?>> docRef,
      ) async {
        final DocumentReference<MyModelType> docRefWithConverter = docRef
            .withConverter(const _ExplicitConverter());
        final DocumentSnapshot<MyModelType> snapshot = await docRefWithConverter
            .get();
        return snapshot.data!;
      });
    });
  });
}
