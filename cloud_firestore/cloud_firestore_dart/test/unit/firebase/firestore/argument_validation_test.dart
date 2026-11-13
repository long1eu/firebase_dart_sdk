// Argument validation of public entry points that must hold in release builds
// too: none of these checks may be an `assert`. (`dart test` runs with asserts
// enabled, so the tests pin the error type: an AssertionError means the check
// is an assert.)

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/lite.dart' as lite;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../../util/test_hygiene.dart';

Matcher throwsArgumentErrorWith(String message) => throwsA(
      isA<ArgumentError>().having(
          (ArgumentError e) => '${e.message}', 'message', contains(message)),
    );

void main() {
  checkTestsLeaveNothingBehind();

  late FirebaseApp app;
  late Firestore firestore;
  late lite.Firestore liteFirestore;
  int apps = 0;

  setUp(() async {
    app = FirebaseApp.withOptions(
      const FirebaseOptions(
          apiKey: 'key', applicationId: 'appId', projectId: 'projectId'),
      dependencies: null,
      name: 'argumentValidation${apps++}',
    );
    firestore = await Firestore.instanceFor(
      app: app,
      settings: FirestoreSettings(cacheSettings: const MemoryCacheSettings()),
    );
    liteFirestore = lite.Firestore.instanceFor(app: app);
    addTearDown(() async {
      await firestore.terminate();
      await liteFirestore.terminate();
      app.delete();
    });
  });

  const String emptyDocument =
      'Invalid document reference. A document path must not be empty.';

  group('document paths', () {
    test('an empty path is rejected', () {
      for (final String path in <String>['', '/']) {
        expect(() => firestore.doc(path), throwsArgumentErrorWith(emptyDocument),
            reason: "doc('$path')");
        // ignore: deprecated_member_use_from_same_package
        expect(() => firestore.document(path),
            throwsArgumentErrorWith(emptyDocument));
        // Relative to a collection the path that results is the collection's.
        expect(
            () => firestore.collection('coll').doc(path),
            throwsArgumentErrorWith(
                'Document references must have an even number of segments, '
                'but coll has 1'));
        expect(() => liteFirestore.doc(path),
            throwsArgumentErrorWith(emptyDocument));
        expect(
            () => liteFirestore.collection('coll').doc(path),
            throwsArgumentErrorWith(
                'Document references must have an even number of segments, '
                'but coll has 1'));
      }
    });

    test('a path with an odd number of segments is rejected', () {
      expect(
          () => firestore.doc('coll'),
          throwsArgumentErrorWith(
              'Document references must have an even number of segments, but '
              'coll has 1'));
      expect(
          () => firestore.doc('coll/doc/sub'),
          throwsArgumentErrorWith(
              'Document references must have an even number of segments, but '
              'coll/doc/sub has 3'));
      expect(
          () => firestore.collection('coll').doc('doc/sub'),
          throwsArgumentErrorWith(
              'Document references must have an even number of segments, but '
              'coll/doc/sub has 3'));
    });

    test('a path with an empty segment is rejected', () {
      const String message = 'Paths must not contain // in them.';
      expect(() => firestore.doc('coll//doc'), throwsArgumentErrorWith(message));
      expect(() => firestore.doc('//coll/doc'),
          throwsArgumentErrorWith(message));
      expect(() => firestore.collection('coll//doc/sub'),
          throwsArgumentErrorWith(message));
      expect(() => firestore.collection('coll').doc('a//b/c'),
          throwsArgumentErrorWith(message));
      expect(() => firestore.doc('coll/doc').collection('a//b'),
          throwsArgumentErrorWith(message));
      expect(() => liteFirestore.doc('coll//doc'),
          throwsArgumentErrorWith(message));
    });

    test('one leading and one trailing slash are ignored', () {
      expect(firestore.doc('/coll/doc/').path, 'coll/doc');
      expect(firestore.collection('/coll/').path, 'coll');
      expect(firestore.collection('coll').doc('/doc/').path, 'coll/doc');
      expect(firestore.doc('coll/doc').collection('/sub/').path,
          'coll/doc/sub');
      expect(liteFirestore.doc('/coll/doc/').path, 'coll/doc');
    });
  });

  group('collection paths', () {
    test('an empty path or one with an even number of segments is rejected',
        () {
      expect(
          () => firestore.collection(''),
          throwsArgumentErrorWith(
              'Collection references must have an odd number of segments, '
              'but  has 0'));
      expect(() => firestore.collection('/'), throwsArgumentError);
      expect(
          () => firestore.collection('coll/doc'),
          throwsArgumentErrorWith(
              'Collection references must have an odd number of segments, '
              'but coll/doc has 2'));
      expect(
          () => firestore.doc('coll/doc').collection(''),
          throwsArgumentErrorWith(
              'Collection references must have an odd number of segments, '
              'but coll/doc has 2'));
      expect(() => firestore.doc('coll/doc').collection('sub/doc'),
          throwsArgumentError);
      expect(() => liteFirestore.collection(''), throwsArgumentError);
      expect(() => liteFirestore.collection('coll/doc'), throwsArgumentError);
    });

    test('a collection group id must be one non-empty segment', () {
      expect(
          () => firestore.collectionGroup(''),
          throwsArgumentErrorWith(
              'Invalid collectionId. Collection IDs must not be empty.'));
      expect(
          () => firestore.collectionGroup('a/b'),
          throwsArgumentErrorWith(
              "Invalid collectionId 'a/b'. Collection IDs must not contain '/'."));
      expect(() => firestore.collectionGroup('/'), throwsArgumentError);
      expect(() => liteFirestore.collectionGroup(''), throwsArgumentError);
      expect(() => liteFirestore.collectionGroup('a/b'), throwsArgumentError);
    });
  });

  group('settings and values', () {
    test('a cache size below the minimum is rejected', () {
      expect(
          () => FirestoreSettings(cacheSizeBytes: 1000),
          throwsArgumentErrorWith(
              'Cache size must be set to at least 1048576 bytes'));
      expect(
          () => FirestoreSettings().copyWith(cacheSizeBytes: 1000),
          throwsArgumentError);
      // No minimum without persistence, and "unlimited" is always accepted.
      expect(
          FirestoreSettings(persistenceEnabled: false, cacheSizeBytes: 1000)
              .cacheSizeBytes,
          1000);
      expect(
          FirestoreSettings(cacheSizeBytes: FirestoreSettings.cacheSizeUnlimited)
              .cacheSizeBytes,
          FirestoreSettings.cacheSizeUnlimited);
      expect(FirestoreSettings(cacheSizeBytes: 1024 * 1024).cacheSizeBytes,
          1024 * 1024);
    });

    test('an app needs an application id', () {
      expect(
        () => FirebaseApp.withOptions(
          _OptionsWithoutApplicationId(),
          dependencies: null,
          name: 'argumentValidationNoAppId',
        ),
        throwsArgumentErrorWith('ApplicationId must be set.'),
      );
    });

    test('an out-of-range GeoPoint is rejected when it is written', () async {
      // What a release build lets through the const constructor.
      final GeoPoint invalid = _OutOfRangeGeoPoint(91, 0);
      final DocumentReference<Map<String, Object?>> doc =
          firestore.doc('coll/doc');
      await expectLater(
          doc.set(<String, Object?>{'where': invalid}),
          throwsArgumentErrorWith(
              'Latitude must be in the range of [-90, 90] but was 91.0'));
      await expectLater(
          doc.set(<String, Object?>{'where': _OutOfRangeGeoPoint(0, -181)}),
          throwsArgumentErrorWith(
              'Longitude must be in the range of [-180, 180] but was -181.0'));
      await expectLater(
          doc.set(<String, Object?>{'where': _OutOfRangeGeoPoint(double.nan, 0)}),
          throwsArgumentErrorWith('Latitude must be in the range'));
      expect(
          () => firestore.collection('coll').where('where', isEqualTo: invalid),
          throwsArgumentErrorWith('Latitude must be in the range'));
    });
  });

  group('AggregateQuerySnapshot equality', () {
    AggregateQuerySnapshot snapshot(
        Map<String, AggregateField> aliases, Map<String, int> values) {
      final AggregateQuery query =
          firestore.collection('coll').aggregateWithAliases(aliases);
      return AggregateQuerySnapshot(query, <String, model.FieldValue>{
        for (final AggregateField field in aliases.values)
          field.alias: model.IntegerValue.valueOf(values[field.alias]!),
      });
    }

    final Map<String, int> values = <String, int>{
      AggregateField.count().alias: 2,
      AggregateField.sum('pages').alias: 150,
    };

    test('does not depend on the order of the aliases', () {
      final AggregateQuerySnapshot a = snapshot(<String, AggregateField>{
        'n': AggregateField.count(),
        'total': AggregateField.sum('pages'),
      }, values);
      final AggregateQuerySnapshot b = snapshot(<String, AggregateField>{
        'total': AggregateField.sum('pages'),
        'n': AggregateField.count(),
      }, values);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('depends on the aliases, the results and the query', () {
      final AggregateQuerySnapshot a = snapshot(
          <String, AggregateField>{'n': AggregateField.count()}, values);
      expect(
          a,
          isNot(snapshot(
              <String, AggregateField>{'m': AggregateField.count()}, values)));
      expect(
          a,
          isNot(snapshot(<String, AggregateField>{'n': AggregateField.count()},
              <String, int>{AggregateField.count().alias: 3})));
      expect(
          a,
          isNot(AggregateQuerySnapshot(
              firestore
                  .collection('other')
                  .aggregateWithAliases(
                      <String, AggregateField>{'n': AggregateField.count()}),
              <String, model.FieldValue>{
                AggregateField.count().alias: model.IntegerValue.valueOf(2),
              })));
    });

    test('without aliases compares the results by aggregation', () {
      AggregateQuerySnapshot of(List<AggregateField> fields) =>
          AggregateQuerySnapshot(
              firestore.collection('coll').aggregate(fields),
              <String, model.FieldValue>{
                for (final AggregateField field in fields)
                  field.alias: model.IntegerValue.valueOf(values[field.alias]!),
              });
      expect(
          of(<AggregateField>[
            AggregateField.count(),
            AggregateField.sum('pages'),
          ]),
          of(<AggregateField>[
            AggregateField.sum('pages'),
            AggregateField.count(),
          ]));
      expect(
          of(<AggregateField>[AggregateField.count()]),
          isNot(of(<AggregateField>[
            AggregateField.count(),
            AggregateField.sum('pages'),
          ])));
    });
  });
}

/// A GeoPoint as a release build would let it through: the range checks of
/// the real constructor are asserts.
// ignore: avoid_implementing_value_types
class _OutOfRangeGeoPoint implements GeoPoint {
  _OutOfRangeGeoPoint(this.latitude, this.longitude);

  @override
  final double latitude;

  @override
  final double longitude;

  @override
  Map<String, Object> toJson() => throw UnimplementedError();

  @override
  int compareTo(GeoPoint other) => throw UnimplementedError();
}

/// Options as a release build would let them through.
// ignore: avoid_implementing_value_types
class _OptionsWithoutApplicationId implements FirebaseOptions {
  @override
  String get applicationId => '';

  @override
  String get apiKey => 'key';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
