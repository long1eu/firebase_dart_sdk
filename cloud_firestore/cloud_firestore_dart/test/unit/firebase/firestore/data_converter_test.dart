import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;

class City {
  const City(this.name, this.population);

  factory City.fromMap(Map<String, Object?> map) =>
      City(map['name']! as String, map['population']! as int);

  final String name;
  final int population;

  Map<String, Object?> toMap() =>
      <String, Object?>{'name': name, 'population': population};
}

City _cityFromFirestore(
        DocumentSnapshot<Map<String, Object?>> snapshot, SnapshotOptions? o) =>
    City.fromMap(snapshot.data!);

Map<String, Object?> _cityToFirestore(City city, SetOptions? options) =>
    city.toMap();

const FirestoreDataConverter<City> cityConverter =
    FirestoreDataConverter<City>.from(
  fromFirestore: _cityFromFirestore,
  toFirestore: _cityToFirestore,
);

class _RecordingClient extends Mock implements FirestoreClient {
  final List<Mutation> written = <Mutation>[];

  @override
  Future<void> write(List<Mutation> mutations) async {
    written.addAll(mutations);
  }
}

class _RecordingConverter extends FirestoreDataConverter<City> {
  SetOptions? lastOptions;
  bool optionsSeen = false;

  @override
  City fromFirestore(DocumentSnapshot<Map<String, Object?>> snapshot,
          SnapshotOptions? o) =>
      City.fromMap(snapshot.data!);

  @override
  Map<String, Object?> toFirestore(City value, SetOptions? options) {
    optionsSeen = true;
    lastOptions = options;
    return value.toMap();
  }
}

void main() {
  late _RecordingClient client;
  late Firestore db;

  setUp(() {
    client = _RecordingClient();
    db = FirestoreInternal.create(
        DatabaseId.forProject('p'), null, client, TaskScheduler('test'));
  });

  Document cityDoc(String path, String name, int pop) =>
      util.doc(path, 1, <String, Object?>{'name': name, 'population': pop});

  group('references', () {
    test('withConverter returns typed references and keeps the path', () {
      final CollectionReference<City> cities =
          db.collection('cities').withConverter<City>(cityConverter);
      expect(cities.path, 'cities');
      expect(cities.converter, same(cityConverter));

      final DocumentReference<City> sf = cities.doc('sf');
      expect(sf.path, 'cities/sf');
      expect(sf.converter, same(cityConverter));
      expect(db.doc('cities/sf').withConverter<City>(cityConverter).path,
          'cities/sf');
    });

    test('withoutConverter resets to raw maps', () {
      final CollectionReference<City> cities =
          db.collection('cities').withConverter<City>(cityConverter);
      final CollectionReference<Map<String, Object?>> raw =
          cities.withoutConverter();
      expect(raw.converter, isNull);
      expect(raw, db.collection('cities'));
      expect(cities.doc('a').withoutConverter(), db.doc('cities/a'));
      expect(cities.whereEqualTo('a', 1).withoutConverter().converter, isNull);
    });

    test('parent and collection() are untyped', () {
      final DocumentReference<City> sf =
          db.doc('cities/sf').withConverter<City>(cityConverter);
      final CollectionReference<Map<String, Object?>> sub =
          sf.collection('landmarks');
      expect(sub.converter, isNull);
      final CollectionReference<Map<String, Object?>> parent = sf.parent;
      expect(parent.converter, isNull);
    });

    test('equality considers the converter', () {
      final DocumentReference<City> a =
          db.doc('cities/sf').withConverter<City>(cityConverter);
      final DocumentReference<City> b =
          db.doc('cities/sf').withConverter<City>(cityConverter);
      // Two converters built from the same canonical functions are equal.
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      final DocumentReference<City> other =
          db.doc('cities/sf').withConverter<City>(_RecordingConverter());
      expect(a, isNot(other));
      expect(a, isNot(db.doc('cities/sf')));

      expect(db.collection('cities').withConverter<City>(cityConverter),
          db.collection('cities').withConverter<City>(cityConverter));
      expect(db.collection('cities').withConverter<City>(cityConverter),
          isNot(db.collection('cities')));
    });

    test('queries keep the converter when refined', () {
      final Query<City> q = db
          .collection('cities')
          .withConverter<City>(cityConverter)
          .whereEqualTo('population', 1)
          .limit(3);
      expect(q.converter, same(cityConverter));
    });
  });

  group('writes', () {
    test('set converts through toFirestore', () async {
      final DocumentReference<City> sf =
          db.doc('cities/sf').withConverter<City>(cityConverter);
      await sf.set(const City('SF', 10));
      final SetMutation m = client.written.single as SetMutation;
      expect(m.key, DocumentKey.fromPathString('cities/sf'));
      expect(m.value,
          util.wrapMap(<String, Object?>{'name': 'SF', 'population': 10}));
    });

    test('set passes SetOptions to the converter; merge is applied', () async {
      final _RecordingConverter converter = _RecordingConverter();
      final DocumentReference<City> sf =
          db.doc('cities/sf').withConverter<City>(converter);
      await sf.set(const City('SF', 10), SetOptions.mergeAllFields);
      expect(converter.lastOptions, same(SetOptions.mergeAllFields));
      expect(client.written.single, isA<PatchMutation>());

      await sf.set(const City('SF', 11));
      expect(converter.optionsSeen, isTrue);
      expect(converter.lastOptions, isNull);
    });

    test('add converts and returns a typed reference', () async {
      final CollectionReference<City> cities =
          db.collection('cities').withConverter<City>(cityConverter);
      final DocumentReference<City> ref = await cities.add(const City('LA', 4));
      expect(ref.converter, same(cityConverter));
      expect(ref.parent.path, 'cities');
      expect((client.written.single as SetMutation).value,
          util.wrapMap(<String, Object?>{'name': 'LA', 'population': 4}));
    });

    test('WriteBatch.set converts, update stays raw', () async {
      final DocumentReference<City> sf =
          db.doc('cities/sf').withConverter<City>(cityConverter);
      final WriteBatch batch = db.batch()
        ..set(sf, const City('SF', 1))
        ..update(sf, <String, Object?>{'population': 2})
        ..delete(sf);
      await batch.commit();
      expect(client.written, hasLength(3));
      expect((client.written[0] as SetMutation).value,
          util.wrapMap(<String, Object?>{'name': 'SF', 'population': 1}));
    });

    test('raw references still accept maps', () async {
      await db.doc('cities/sf').set(<String, Object?>{'name': 'SF'});
      expect(client.written.single, isA<SetMutation>());
    });
  });

  group('snapshots', () {
    test('DocumentSnapshot.data converts, missing documents give null', () {
      final DocumentSnapshot<City> snap = DocumentSnapshotInternal.fromDocument<City>(
        db,
        cityDoc('cities/sf', 'SF', 10),
        isFromCache: false,
        hasPendingWrites: false,
        converter: cityConverter,
      );
      expect(snap.exists, isTrue);
      expect(snap.data!.name, 'SF');
      expect(snap.data!.population, 10);
      expect(snap.getData(ServerTimestampBehavior.none)!.name, 'SF');
      expect(snap.ref.converter, same(cityConverter));
      expect(snap.ref.path, 'cities/sf');
      // Field access stays raw.
      expect(snap.get('population'), 10);

      final DocumentSnapshot<City> missing =
          DocumentSnapshotInternal.fromNoDocument<City>(
        db,
        DocumentKey.fromPathString('cities/none'),
        isFromCache: false,
        hasPendingWrites: false,
        converter: cityConverter,
      );
      expect(missing.exists, isFalse);
      expect(missing.data, isNull);
    });

    test('the converter receives an untyped QueryDocumentSnapshot', () {
      DocumentSnapshot<Map<String, Object?>>? seen;
      SnapshotOptions? seenOptions;
      final FirestoreDataConverter<int> c = FirestoreDataConverter<int>.from(
        fromFirestore:
            (DocumentSnapshot<Map<String, Object?>> s, SnapshotOptions? o) {
          seen = s;
          seenOptions = o;
          return s.data!['population']! as int;
        },
        toFirestore: (int v, SetOptions? o) =>
            <String, Object?>{'population': v},
      );
      final DocumentSnapshot<int> snap = DocumentSnapshotInternal.fromDocument<int>(
        db,
        cityDoc('cities/sf', 'SF', 10),
        isFromCache: true,
        hasPendingWrites: false,
        converter: c,
      );
      expect(snap.getData(ServerTimestampBehavior.estimate), 10);
      expect(seen, isA<QueryDocumentSnapshot<Map<String, Object?>>>());
      expect(seen!.metadata.isFromCache, isTrue);
      expect(seenOptions!.serverTimestamps, ServerTimestampBehavior.estimate);
    });

    test('QuerySnapshot and DocumentChange are typed', () {
      final Document d1 = cityDoc('cities/a', 'A', 1);
      final Document d2 = cityDoc('cities/b', 'B', 2);
      final DocumentSet docs =
          util.docSet(Document.keyComparator).add(d1).add(d2);
      final ViewSnapshot view = ViewSnapshot(
        util.query('cities'),
        docs,
        util.docSet(Document.keyComparator),
        <DocumentViewChange>[
          DocumentViewChange(DocumentViewChangeType.added, d1),
          DocumentViewChange(DocumentViewChangeType.added, d2),
        ],
        DocumentKey.emptyKeySet,
        isFromCache: false,
        didSyncStateChange: true,
        excludesMetadataChanges: false,
        hasCachedResults: false,
      );
      final Query<City> query =
          QueryInternal.create<City>(util.query('cities'), db, cityConverter);
      final QuerySnapshot<City> snapshot = QuerySnapshotInternal.create<City>(query, view, db);

      expect(snapshot.length, 2);
      final List<QueryDocumentSnapshot<City>> list = snapshot.docs;
      expect(list.map((QueryDocumentSnapshot<City> s) => s.data.name),
          <String>['A', 'B']);
      expect(
          snapshot.docChanges
              .map((DocumentChange<City> c) => c.document.data.population),
          <int>[1, 2]);
      expect(snapshot.query.converter, same(cityConverter));
    });

    test('untyped usage is unchanged', () {
      final DocumentSnapshot<Map<String, Object?>> snap =
          DocumentSnapshotInternal.fromDocument<Map<String, Object?>>(
        db,
        cityDoc('cities/sf', 'SF', 10),
        isFromCache: false,
        hasPendingWrites: false,
      );
      expect(snap.data, <String, Object?>{'name': 'SF', 'population': 10});
    });
  });
}
