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
Firestore _TestFirestore() =>
    FirestoreInternal.detached(DatabaseId.forProject('project'));

/// Backend-free port of the query related cases of upstream ValidationTest
/// (which the Dart port only has as an emulator integration test).
void main() {
  final Firestore db = _TestFirestore();
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
          collection().whereGreaterThan('a', 1).whereLessThan('b', 1);
      expect(q.query.inequalityFilterFields.length, 2);
      expect(collection().whereNotEqualTo('a', 1).whereLessThan('b', 1),
          isA<Query>());
      expect(
          collection().whereNotIn('a', <int>[1]).whereGreaterThan('b', 1),
          isA<Query>());
    });

    test('inequality filters on the same field are allowed', () {
      expect(collection().whereGreaterThan('a', 1).whereLessThan('a', 5),
          isA<Query>());
    });

    test('the first orderBy does not have to match the inequality field', () {
      expect(collection().whereGreaterThan('a', 1).orderBy('b'), isA<Query>());
      expect(collection().orderBy('b').whereGreaterThan('a', 1), isA<Query>());
      expect(collection().whereGreaterThan('a', 1).orderBy('a').orderBy('b'),
          isA<Query>());
      // The implicit inequality orderings are appended after the explicit one.
      expect(
          collection()
              .whereGreaterThan('a', 1)
              .orderBy('b')
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
          collection().whereArrayContains('a', 1).whereArrayContains('b', 2),
          isA<Query>());
      expect(
          collection()
              .whereArrayContains('a', 1)
              .whereArrayContainsAny('b', <int>[1]),
          isA<Query>());
      expect(collection().whereIn('a', <int>[1]).whereIn('b', <int>[1]),
          isA<Query>());
      expect(
          collection()
              .whereIn('a', <int>[1]).whereArrayContainsAny('b', <int>[1]),
          isA<Query>());
      expect(
          collection().whereArrayContainsAny(
              'a', <int>[1]).whereArrayContainsAny('b', <int>[1]),
          isA<Query>());
    });

    test('in / array-contains-any / not-in need a non-empty list', () {
      expect(() => collection().whereIn('a', <int>[]),
          throwsInvalidQuery('A non-empty array is required for "in" filters'));
      expect(
          () => collection().whereArrayContainsAny('a', <int>[]),
          throwsInvalidQuery(
              'A non-empty array is required for "array-contains-any" filters'));
      expect(
          () => collection().whereNotIn('a', <int>[]),
          throwsInvalidQuery(
              'A non-empty array is required for "not-in" filters'));
    });

    test('the number of values in a disjunctive filter is not limited', () {
      final List<int> eleven = List<int>.generate(11, (int i) => i);
      expect(collection().whereIn('a', eleven), isA<Query>());
      expect(collection().whereArrayContainsAny('a', eleven), isA<Query>());
      expect(collection().whereNotIn('a', eleven), isA<Query>());
    });

    test('only one not-equal filter', () {
      expect(() => collection().whereNotEqualTo('a', 1).whereNotEqualTo('a', 2),
          throwsInvalidQuery('You cannot use more than one \'!=\' filter'));
    });

    test('not-in cannot be combined with in, not-in, != or array-contains-any',
        () {
      for (final Query Function(Query) other in <Query Function(Query)>[
        (Query q) => q.whereNotEqualTo('a', 1),
        (Query q) => q.whereIn('a', <int>[1]),
        (Query q) => q.whereArrayContainsAny('a', <int>[1]),
        (Query q) => q.whereNotIn('a', <int>[1]),
      ]) {
        expect(() => other(collection()).whereNotIn('a', <int>[2]),
            throwsInvalidQuery('Invalid query. You cannot use'));
        expect(() => collection().whereNotIn('a', <int>[2]), returnsNormally);
      }
      expect(
          () => collection().whereNotIn('a', <int>[2]).whereNotEqualTo('a', 1),
          throwsInvalidQuery(
              'You cannot use \'!=\' filters with \'not-in\' filters'));
      expect(
          () => collection().whereNotIn('a', <int>[2]).whereIn('a', <int>[1]),
          throwsInvalidQuery('You cannot use \'in\' filters with \'not-in\''));
      // array-contains is not in conflict with not-in anymore.
      expect(
          collection().whereArrayContains('a', 1).whereNotIn('b', <int>[2]),
          isA<Query>());
    });

    test('array-contains cannot be used on the document id', () {
      expect(
          () => collection()
              .whereArrayContainsField(FieldPath.documentIdField, 'x'),
          throwsInvalidQuery(
              'You can\'t perform "array-contains" queries on FieldPath.documentId()'));
      expect(
          () => collection().whereArrayContainsAnyField(
              FieldPath.documentIdField, <String>['x']),
          throwsInvalidQuery(
              'You can\'t perform "array-contains-any" queries on FieldPath.documentId()'));
    });

    test('document id values must be plain ids in a collection query', () {
      expect(
          () => collection().whereEqualToField(FieldPath.documentIdField, ''),
          throwsInvalidQuery('but it was an empty string'));
      expect(
          () =>
              collection().whereEqualToField(FieldPath.documentIdField, 'a/b'),
          throwsInvalidQuery('contains a "/" character'));
      expect(
          () => collection().whereEqualToField(FieldPath.documentIdField, 1),
          throwsInvalidQuery(
              'you must provide a valid String or DocumentReference'));
      expect(
          () => collection().whereInField(FieldPath.documentIdField, <int>[1]),
          throwsInvalidQuery(
              'you must provide a valid String or DocumentReference'));
      expect(collection().whereEqualToField(FieldPath.documentIdField, 'abc'),
          isA<Query>());
    });

    test('filters are applied to the core query', () {
      final Query q = collection()
          .whereEqualTo('a', 1)
          .whereGreaterThanOrEqualTo('b', 2)
          .orderBy('b', Direction.descending);
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
      final Query q = collection().orderByField(FieldPath.documentIdField);
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
          collection()
              .orderBy('a')
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
      expect(collection().where(Filter.equalTo('a', 1)),
          collection().whereEqualTo('a', 1));
      expect(collection().where(Filter.notEqualTo('a', 1)),
          collection().whereNotEqualTo('a', 1));
      expect(collection().where(Filter.greaterThan('a', 1)),
          collection().whereGreaterThan('a', 1));
      expect(collection().where(Filter.greaterThanOrEqualTo('a', 1)),
          collection().whereGreaterThanOrEqualTo('a', 1));
      expect(collection().where(Filter.lessThan('a', 1)),
          collection().whereLessThan('a', 1));
      expect(collection().where(Filter.lessThanOrEqualTo('a', 1)),
          collection().whereLessThanOrEqualTo('a', 1));
      expect(collection().where(Filter.arrayContains('a', 1)),
          collection().whereArrayContains('a', 1));
      expect(collection().where(Filter.arrayContainsAny('a', <int>[1, 2])),
          collection().whereArrayContainsAny('a', <int>[1, 2]));
      expect(collection().where(Filter.inArray('a', <int>[1, 2])),
          collection().whereIn('a', <int>[1, 2]));
      expect(collection().where(Filter.notInArray('a', <int>[1, 2])),
          collection().whereNotIn('a', <int>[1, 2]));
    });

    test('the FieldPath variants build the same filters', () {
      final FieldPath path = FieldPath.fromDotSeparatedPath('a.b');
      expect(Filter.equalToField(path, 1), Filter.equalTo('a.b', 1));
      expect(Filter.notEqualToField(path, 1), Filter.notEqualTo('a.b', 1));
      expect(Filter.greaterThanField(path, 1), Filter.greaterThan('a.b', 1));
      expect(Filter.greaterThanOrEqualToField(path, 1),
          Filter.greaterThanOrEqualTo('a.b', 1));
      expect(Filter.lessThanField(path, 1), Filter.lessThan('a.b', 1));
      expect(Filter.lessThanOrEqualToField(path, 1),
          Filter.lessThanOrEqualTo('a.b', 1));
      expect(
          Filter.arrayContainsField(path, 1), Filter.arrayContains('a.b', 1));
      expect(Filter.arrayContainsAnyField(path, <int>[1]),
          Filter.arrayContainsAny('a.b', <int>[1]));
      expect(Filter.inArrayField(path, <int>[1]),
          Filter.inArray('a.b', <int>[1]));
      expect(Filter.notInArrayField(path, <int>[1]),
          Filter.notInArray('a.b', <int>[1]));
      expect(Filter.equalTo('a', 1), isNot(Filter.equalTo('a', 2)));
      expect(Filter.equalTo('a', 1), isNot(Filter.notEqualTo('a', 1)));
    });

    test('composite filters compare by operator and filters', () {
      final Filter a = Filter.equalTo('a', 1);
      final Filter b = Filter.equalTo('b', 2);
      expect(Filter.or(<Filter>[a, b]), Filter.or(<Filter>[a, b]));
      expect(Filter.or(<Filter>[a, b]).hashCode,
          Filter.or(<Filter>[a, b]).hashCode);
      expect(Filter.or(<Filter>[a, b]), isNot(Filter.and(<Filter>[a, b])));
      expect(Filter.or(<Filter>[a, b]), isNot(Filter.or(<Filter>[b, a])));
    });

    test('OR filters build a disjunction', () {
      final Query q = collection().where(Filter.or(
          <Filter>[Filter.equalTo('a', 1), Filter.greaterThan('b', 2)]));
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
              <Filter>[Filter.equalTo('a', 1), Filter.equalTo('b', 2)])),
          collection().whereEqualTo('a', 1).whereEqualTo('b', 2));
    });

    test('composite filters with one filter collapse to that filter', () {
      expect(collection().where(Filter.or(<Filter>[Filter.equalTo('a', 1)])),
          collection().whereEqualTo('a', 1));
      expect(
          collection().where(Filter.and(<Filter>[
            Filter.or(<Filter>[Filter.equalTo('a', 1)])
          ])),
          collection().whereEqualTo('a', 1));
    });

    test('empty composite filters return the same query', () {
      final Query q = collection().whereEqualTo('a', 1);
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
                Filter.equalTo('a', 1),
                Filter.and(<Filter>[Filter.inArray('b', <int>[])]),
              ])),
          throwsInvalidQuery('A non-empty array is required for "in" filters'));
      expect(
          () => collection().where(Filter.or(<Filter>[
                Filter.equalTo('a', 1),
                Filter.arrayContainsField(FieldPath.documentIdField, 1),
              ])),
          throwsInvalidQuery('You can\'t perform "array-contains" queries'));
      expect(
          () => collection().where(Filter.or(<Filter>[
                Filter.equalToField(FieldPath.documentIdField, 'a/b'),
                Filter.equalTo('a', 1),
              ])),
          throwsInvalidQuery('contains a "/" character'));
      expect(
          () => collection().where(Filter.equalTo('a', Object())),
          throwsA(anything));
    });

    test('conflicting operators are detected across composite filters', () {
      // A new composite filter against the filters of the query.
      expect(
          () => collection().whereNotEqualTo('a', 1).where(Filter.or(<Filter>[
                Filter.equalTo('b', 1),
                Filter.notInArray('c', <int>[1]),
              ])),
          throwsInvalidQuery('You cannot use \'not-in\' filters with \'!=\''));
      // A new filter against the filters nested in a composite filter.
      expect(
          () => collection()
              .where(Filter.or(<Filter>[
                Filter.equalTo('b', 1),
                Filter.inArray('c', <int>[1]),
              ]))
              .whereNotIn('d', <int>[2]),
          throwsInvalidQuery('You cannot use \'not-in\' filters with \'in\''));
      // Within a single composite filter.
      expect(
          () => collection().where(Filter.and(<Filter>[
                Filter.notEqualTo('a', 1),
                Filter.or(<Filter>[
                  Filter.equalTo('b', 1),
                  Filter.notEqualTo('c', 1),
                ]),
              ])),
          throwsInvalidQuery('You cannot use more than one \'!=\' filter'));
      expect(
          () => collection().where(Filter.or(<Filter>[
                Filter.notInArray('a', <int>[1]),
                Filter.notInArray('b', <int>[1]),
              ])),
          throwsInvalidQuery('You cannot use more than one \'not-in\' filter'));
    });

    test('several in / array-contains filters are allowed in OR queries', () {
      expect(
          collection().where(Filter.or(<Filter>[
            Filter.inArray('a', <int>[1, 2]),
            Filter.inArray('b', <int>[1, 2]),
            Filter.and(<Filter>[
              Filter.arrayContains('c', 1),
              Filter.arrayContains('d', 1),
            ]),
            Filter.arrayContainsAny('e', <int>[1, 2]),
          ])),
          isA<Query>());
    });
  });

  test('field path based variants build the same query as string variants', () {
    expect(
        collection().whereEqualTo('a.b', 1),
        collection()
            .whereEqualToField(FieldPath.fromDotSeparatedPath('a.b'), 1));
    expect(collection().orderBy('a.b'),
        collection().orderByField(FieldPath.fromDotSeparatedPath('a.b')));
  });
}
