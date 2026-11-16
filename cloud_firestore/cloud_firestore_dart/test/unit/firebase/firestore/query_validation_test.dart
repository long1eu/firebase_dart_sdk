// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart'
    show CompositeFilter;
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart'
    show Filter;
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;
import 'test_util.dart' as unit;

// ignore: non_constant_identifier_names
FirebaseFirestore _TestFirestore() =>
    FirestoreInternal.detached(DatabaseId.forProject('project'));

/// Backend-free port of the query related cases of upstream ValidationTest
/// (which the Dart port only has as an emulator integration test).
void main() {
  final FirebaseFirestore db = _TestFirestore();
  Query collection() => QueryInternal.create(util.query('collection'), db);

  Matcher throwsInvalidQuery([Pattern? message]) => throwsA(
        isA<ArgumentError>().having((ArgumentError e) => e.message.toString(),
            'message', message == null ? isNotEmpty : contains(message)),
      );

  group('limit', () {
    test('must be positive', () {
      expect(() => collection().limit(0),
          throwsInvalidQuery('Limit must be positive'));
      expect(() => collection().limit(-1),
          throwsInvalidQuery('Limit must be positive'));
      expect(collection().limit(1).query.getLimit(), 1);
    });
  });

  group('filters', () {
    // Multiple inequality filters (upstream c5a894c): the client no longer
    // restricts the inequality fields, the backend validates them.
    test('inequality filters on different fields are allowed', () {
      final Query q =
          collection().where('a', isGreaterThan: 1).where('b', isLessThan: 1);
      expect(q.query.inequalityFilterFields.length, 2);
      expect(collection().where('a', isNotEqualTo: 1).where('b', isLessThan: 1),
          isA<Query>());
      expect(
          collection().where('a', whereNotIn: <int>[1]).where('b', isGreaterThan: 1),
          isA<Query>());
    });

    test('inequality filters on the same field are allowed', () {
      expect(collection().where('a', isGreaterThan: 1).where('a', isLessThan: 5),
          isA<Query>());
    });

    test('the first orderBy does not have to match the inequality field', () {
      expect(collection().where('a', isGreaterThan: 1).orderBy('b'), isA<Query>());
      expect(collection().orderBy('b').where('a', isGreaterThan: 1), isA<Query>());
      expect(collection().where('a', isGreaterThan: 1).orderBy('a').orderBy('b'),
          isA<Query>());
      // The implicit inequality orderings are appended after the explicit one.
      expect(
          collection()
              .where('a', isGreaterThan: 1).orderBy('b')
              .query
              .orderByConstraints
              .map((o) => o.field.canonicalString)
              .toList(),
          <String>['b', 'a', '__name__']);
    });

    test('array-contains and disjunctive filters can be combined', () {
      // These combinations were rejected before OR queries; they are now
      // validated by the backend only.
      expect(
          collection().where('a', arrayContains: 1).where('b', arrayContains: 2),
          isA<Query>());
      expect(
          collection()
              .where('a', arrayContains: 1).where('b', arrayContainsAny: <int>[1]),
          isA<Query>());
      expect(collection().where('a', whereIn: <int>[1]).where('b', whereIn: <int>[1]),
          isA<Query>());
      expect(
          collection()
              .where('a', whereIn: <int>[1]).where('b', arrayContainsAny: <int>[1]),
          isA<Query>());
      expect(
          collection().where(
              'a', arrayContainsAny: <int>[1]).where('b', arrayContainsAny: <int>[1]),
          isA<Query>());
    });

    test('in / array-contains-any / not-in need a non-empty list', () {
      expect(() => collection().where('a', whereIn: <int>[]),
          throwsInvalidQuery('A non-empty array is required for "in" filters'));
      expect(
          () => collection().where('a', arrayContainsAny: <int>[]),
          throwsInvalidQuery(
              'A non-empty array is required for "array-contains-any" filters'));
      expect(
          () => collection().where('a', whereNotIn: <int>[]),
          throwsInvalidQuery(
              'A non-empty array is required for "not-in" filters'));
    });

    test('the number of values in a disjunctive filter is not limited', () {
      final List<int> eleven = List<int>.generate(11, (int i) => i);
      expect(collection().where('a', whereIn: eleven), isA<Query>());
      expect(collection().where('a', arrayContainsAny: eleven), isA<Query>());
      expect(collection().where('a', whereNotIn: eleven), isA<Query>());
    });

    test('only one not-equal filter', () {
      expect(() => collection().where('a', isNotEqualTo: 1).where('a', isNotEqualTo: 2),
          throwsInvalidQuery('You cannot use more than one \'!=\' filter'));
    });

    test('not-in cannot be combined with in, not-in, != or array-contains-any',
        () {
      for (final Query Function(Query) other in <Query Function(Query)>[
        (Query q) => q.where('a', isNotEqualTo: 1),
        (Query q) => q.where('a', whereIn: <int>[1]),
        (Query q) => q.where('a', arrayContainsAny: <int>[1]),
        (Query q) => q.where('a', whereNotIn: <int>[1]),
      ]) {
        expect(() => other(collection()).where('a', whereNotIn: <int>[2]),
            throwsInvalidQuery('Invalid query. You cannot use'));
        expect(() => collection().where('a', whereNotIn: <int>[2]), returnsNormally);
      }
      expect(
          () => collection().where('a', whereNotIn: <int>[2]).where('a', isNotEqualTo: 1),
          throwsInvalidQuery(
              'You cannot use \'!=\' filters with \'not-in\' filters'));
      expect(
          () => collection().where('a', whereNotIn: <int>[2]).where('a', whereIn: <int>[1]),
          throwsInvalidQuery('You cannot use \'in\' filters with \'not-in\''));
      // array-contains is not in conflict with not-in anymore.
      expect(
          collection().where('a', arrayContains: 1).where('b', whereNotIn: <int>[2]),
          isA<Query>());
    });

    test('array-contains cannot be used on the document id', () {
      expect(
          () => collection().where(FieldPath.documentId, arrayContains: 'x'),
          throwsInvalidQuery(
              'You can\'t perform "array-contains" queries on FieldPath.documentId'));
      expect(
          () => collection().where(FieldPath.documentId, arrayContainsAny: <String>['x']),
          throwsInvalidQuery(
              'You can\'t perform "array-contains-any" queries on FieldPath.documentId'));
    });

    test('document id values must be plain ids in a collection query', () {
      expect(
          () => collection().where(FieldPath.documentId, isEqualTo: ''),
          throwsInvalidQuery('but it was an empty string'));
      expect(
          () =>
              collection().where(FieldPath.documentId, isEqualTo: 'a/b'),
          throwsInvalidQuery('contains a "/" character'));
      expect(
          () => collection().where(FieldPath.documentId, isEqualTo: 1),
          throwsInvalidQuery(
              'you must provide a valid String or DocumentReference'));
      expect(
          () => collection().where(FieldPath.documentId, whereIn: <int>[1]),
          throwsInvalidQuery(
              'you must provide a valid String or DocumentReference'));
      expect(collection().where(FieldPath.documentId, isEqualTo: 'abc'),
          isA<Query>());
    });

    test('filters are applied to the core query', () {
      final Query q = collection()
          .where('a', isEqualTo: 1)
          .where('b', isGreaterThanOrEqualTo: 2).orderBy('b', descending: true);
      expect(q.query.filters.length, 2);
      expect(q.query.explicitSortOrder.length, 1);
      expect(q.query, isNot(collection().query));
    });
  });

  group('bounds', () {
    test('too many arguments', () {
      expect(() => collection().orderBy('a').startAt(<Object>[1, 2]),
          throwsInvalidQuery('Too many arguments provided to startAt()'));
      expect(() => collection().orderBy('a').endBefore(<Object>[1, 2]),
          throwsInvalidQuery('Too many arguments provided to endBefore()'));
      expect(() => collection().startAfter(<Object>[1]),
          throwsInvalidQuery('Too many arguments provided to startAfter()'));
    });

    test('document id bounds must be strings without slashes', () {
      final Query q = collection().orderBy(FieldPath.documentId);
      expect(() => q.startAt(<Object>[1]),
          throwsInvalidQuery('Expected a string for document ID in startAt()'));
      expect(() => q.endAt(<Object>['a/b']),
          throwsInvalidQuery('must be a plain document ID'));
      expect(q.startAt(<Object>['abc']), isA<Query>());
    });

    test('a non-existent document cannot be used as a cursor', () {
      final DocumentSnapshot missing =
          unit.documentSnapshot('collection/x', null, false);
      expect(() => collection().startAtDocument(missing),
          throwsInvalidQuery('document that doesn\'t exist'));
      expect(() => collection().endAtDocument(missing),
          throwsInvalidQuery('document that doesn\'t exist'));
    });

    test('a document missing an orderBy field cannot be used as a cursor', () {
      final DocumentSnapshot snap = unit.documentSnapshot(
          'collection/x', util.map<Object>(<Object>['a', 1]), false);
      expect(() => collection().orderBy('missing').startAtDocument(snap),
          throwsInvalidQuery('does not exist'));
    });

    test('a document cursor adds all the order-by components', () {
      final DocumentSnapshot snap = unit.documentSnapshot(
          'collection/x', util.map<Object>(<Object>['a', 1]), false);
      final Query q = collection().orderBy('a').startAtDocument(snap);
      expect(q.query.getStartAt(), isNotNull);
      // `a` plus the implicit document key.
      expect(q.query.getStartAt()!.position.length, 2);
      expect(q.query.getStartAt()!.inclusive, isTrue);
      expect(
          collection().orderBy('a')
              .startAfterDocument(snap)
              .query
              .getStartAt()!
              .inclusive,
          isFalse);
    });

    test('orderBy cannot be called after startAt or startAfter', () {
      final Query q = collection().orderBy('a').startAt(<Object>[1]);
      expect(() => q.orderBy('b'),
          throwsInvalidQuery('You must not call Query.startAt()'));
      expect(
          () => collection().orderBy('a').startAfter(<Object>[1]).orderBy('b'),
          throwsInvalidQuery('You must not call Query.startAt()'));
    });

    test('orderBy cannot be called after endAt or endBefore', () {
      expect(() => collection().orderBy('a').endAt(<Object>[1]).orderBy('b'),
          throwsInvalidQuery('You must not call Query.endAt()'));
      expect(
          () => collection().orderBy('a').endBefore(<Object>[1]).orderBy('b'),
          throwsInvalidQuery('You must not call Query.endAt()'));
    });
  });

  group('where(Filter) and Filter.or / Filter.and', () {
    test('a field filter builds the same query as the where* helpers', () {
      expect(collection().where(Filter('a', isEqualTo: 1)),
          collection().where('a', isEqualTo: 1));
      expect(collection().where(Filter('a', isNotEqualTo: 1)),
          collection().where('a', isNotEqualTo: 1));
      expect(collection().where(Filter('a', isGreaterThan: 1)),
          collection().where('a', isGreaterThan: 1));
      expect(collection().where(Filter('a', isGreaterThanOrEqualTo: 1)),
          collection().where('a', isGreaterThanOrEqualTo: 1));
      expect(collection().where(Filter('a', isLessThan: 1)),
          collection().where('a', isLessThan: 1));
      expect(collection().where(Filter('a', isLessThanOrEqualTo: 1)),
          collection().where('a', isLessThanOrEqualTo: 1));
      expect(collection().where(Filter('a', arrayContains: 1)),
          collection().where('a', arrayContains: 1));
      expect(collection().where(Filter('a', arrayContainsAny: <int>[1, 2])),
          collection().where('a', arrayContainsAny: <int>[1, 2]));
      expect(collection().where(Filter('a', whereIn: <int>[1, 2])),
          collection().where('a', whereIn: <int>[1, 2]));
      expect(collection().where(Filter('a', whereNotIn: <int>[1, 2])),
          collection().where('a', whereNotIn: <int>[1, 2]));
    });

    test('the FieldPath variants build the same filters', () {
      final FieldPath path = FieldPath.fromString('a.b');
      expect(Filter(path, isEqualTo: 1), Filter('a.b', isEqualTo: 1));
      expect(Filter(path, isNotEqualTo: 1), Filter('a.b', isNotEqualTo: 1));
      expect(Filter(path, isGreaterThan: 1), Filter('a.b', isGreaterThan: 1));
      expect(Filter(path, isGreaterThanOrEqualTo: 1),
          Filter('a.b', isGreaterThanOrEqualTo: 1));
      expect(Filter(path, isLessThan: 1), Filter('a.b', isLessThan: 1));
      expect(Filter(path, isLessThanOrEqualTo: 1),
          Filter('a.b', isLessThanOrEqualTo: 1));
      expect(
          Filter(path, arrayContains: 1), Filter('a.b', arrayContains: 1));
      expect(Filter(path, arrayContainsAny: <int>[1]),
          Filter('a.b', arrayContainsAny: <int>[1]));
      expect(Filter(path, whereIn: <int>[1]),
          Filter('a.b', whereIn: <int>[1]));
      expect(Filter(path, whereNotIn: <int>[1]),
          Filter('a.b', whereNotIn: <int>[1]));
      expect(Filter('a', isEqualTo: 1), isNot(Filter('a', isEqualTo: 2)));
      expect(Filter('a', isEqualTo: 1), isNot(Filter('a', isNotEqualTo: 1)));
    });

    test('composite filters compare by operator and filters', () {
      final Filter a = Filter('a', isEqualTo: 1);
      final Filter b = Filter('b', isEqualTo: 2);
      expect(Filter.or(<Filter>[a, b]), Filter.or(<Filter>[a, b]));
      expect(Filter.or(<Filter>[a, b]).hashCode,
          Filter.or(<Filter>[a, b]).hashCode);
      expect(Filter.or(<Filter>[a, b]), isNot(Filter.and(<Filter>[a, b])));
      expect(Filter.or(<Filter>[a, b]), isNot(Filter.or(<Filter>[b, a])));
    });

    test('OR filters build a disjunction', () {
      final Query q = collection().where(Filter.or(
          <Filter>[Filter('a', isEqualTo: 1), Filter('b', isGreaterThan: 2)]));
      expect(q.query.filters.length, 1);
      final CompositeFilter composite = q.query.filters[0] as CompositeFilter;
      expect(composite.isDisjunction, isTrue);
      expect(composite.filters.length, 2);
      // The inequality of the second filter adds an implicit orderBy.
      expect(q.query.orderByConstraints.first.field.canonicalString, 'b');
    });

    test('AND filters are the same query as chained where clauses', () {
      expect(
          collection().where(Filter.and(
              <Filter>[Filter('a', isEqualTo: 1), Filter('b', isEqualTo: 2)])),
          collection().where('a', isEqualTo: 1).where('b', isEqualTo: 2));
    });

    test('composite filters with one filter collapse to that filter', () {
      expect(collection().where(Filter.or(<Filter>[Filter('a', isEqualTo: 1)])),
          collection().where('a', isEqualTo: 1));
      expect(
          collection().where(Filter.and(<Filter>[
            Filter.or(<Filter>[Filter('a', isEqualTo: 1)])
          ])),
          collection().where('a', isEqualTo: 1));
    });

    test('empty composite filters return the same query', () {
      final Query q = collection().where('a', isEqualTo: 1);
      expect(identical(q.where(Filter.or(<Filter>[])), q), isTrue);
      expect(identical(q.where(Filter.and(<Filter>[])), q), isTrue);
      expect(
          identical(
              q.where(Filter.or(<Filter>[
                Filter.and(<Filter>[])
              ])),
              q),
          isTrue);
    });

    test('nested filters are validated and their values parsed', () {
      expect(
          () => collection().where(Filter.or(<Filter>[
                Filter('a', isEqualTo: 1),
                Filter.and(<Filter>[Filter('b', whereIn: <int>[])]),
              ])),
          throwsInvalidQuery('A non-empty array is required for "in" filters'));
      expect(
          () => collection().where(Filter.or(<Filter>[
                Filter('a', isEqualTo: 1),
                Filter(FieldPath.documentId, arrayContains: 1),
              ])),
          throwsInvalidQuery('You can\'t perform "array-contains" queries'));
      expect(
          () => collection().where(Filter.or(<Filter>[
                Filter(FieldPath.documentId, isEqualTo: 'a/b'),
                Filter('a', isEqualTo: 1),
              ])),
          throwsInvalidQuery('contains a "/" character'));
      expect(
          () => collection().where(Filter('a', isEqualTo: Object())),
          throwsA(anything));
    });

    test('conflicting operators are detected across composite filters', () {
      // A new composite filter against the filters of the query.
      expect(
          () => collection().where('a', isNotEqualTo: 1).where(Filter.or(<Filter>[
                Filter('b', isEqualTo: 1),
                Filter('c', whereNotIn: <int>[1]),
              ])),
          throwsInvalidQuery('You cannot use \'not-in\' filters with \'!=\''));
      // A new filter against the filters nested in a composite filter.
      expect(
          () => collection()
              .where(Filter.or(<Filter>[
                Filter('b', isEqualTo: 1),
                Filter('c', whereIn: <int>[1]),
              ])).where('d', whereNotIn: <int>[2]),
          throwsInvalidQuery('You cannot use \'not-in\' filters with \'in\''));
      // Within a single composite filter.
      expect(
          () => collection().where(Filter.and(<Filter>[
                Filter('a', isNotEqualTo: 1),
                Filter.or(<Filter>[
                  Filter('b', isEqualTo: 1),
                  Filter('c', isNotEqualTo: 1),
                ]),
              ])),
          throwsInvalidQuery('You cannot use more than one \'!=\' filter'));
      expect(
          () => collection().where(Filter.or(<Filter>[
                Filter('a', whereNotIn: <int>[1]),
                Filter('b', whereNotIn: <int>[1]),
              ])),
          throwsInvalidQuery('You cannot use more than one \'not-in\' filter'));
    });

    test('several in / array-contains filters are allowed in OR queries', () {
      expect(
          collection().where(Filter.or(<Filter>[
            Filter('a', whereIn: <int>[1, 2]),
            Filter('b', whereIn: <int>[1, 2]),
            Filter.and(<Filter>[
              Filter('c', arrayContains: 1),
              Filter('d', arrayContains: 1),
            ]),
            Filter('e', arrayContainsAny: <int>[1, 2]),
          ])),
          isA<Query>());
    });
  });

  test('field path based variants build the same query as string variants', () {
    expect(
        collection().where('a.b', isEqualTo: 1),
        collection().where(FieldPath.fromString('a.b'), isEqualTo: 1));
    expect(collection().orderBy('a.b'),
        collection().orderBy(FieldPath.fromString('a.b')));
  });
}
