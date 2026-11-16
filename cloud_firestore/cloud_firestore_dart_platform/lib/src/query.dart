import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as pi;
import 'package:collection/collection.dart';

import 'aggregate_query.dart';
import 'errors.dart';
import 'firestore.dart';
import 'snapshots.dart';
import 'value_codec.dart';

/// A [QueryPlatform] backed by `cloud_firestore_dart`.
///
/// Like the method channel implementation, it keeps the query as the
/// [parameters] map that `cloud_firestore` reads and extends (`where`,
/// `orderBy`, `filters`, the cursors and the limits), and builds the
/// `cloud_firestore_dart` query from it when the query runs.
class DartQuery extends QueryPlatform {
  /// The query over the collection at [path] of [firestore], or over every
  /// collection with the id [path] when [isCollectionGroupQuery] is set.
  DartQuery(
    DartFirebaseFirestore firestore,
    this.path, {
    Map<String, dynamic>? parameters,
    this.isCollectionGroupQuery = false,
  }) : super(firestore, parameters);

  /// The collection path, or the collection id of a collection group query.
  final String path;

  @override
  final bool isCollectionGroupQuery;

  DartFirebaseFirestore get _firestore => firestore as DartFirebaseFirestore;

  DartQuery _copyWith(Map<String, dynamic> changes) {
    return DartQuery(
      _firestore,
      path,
      isCollectionGroupQuery: isCollectionGroupQuery,
      parameters: Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(parameters)..addAll(changes),
      ),
    );
  }

  /// The `cloud_firestore_dart` query that [parameters] describe.
  fs.Query<Map<String, Object?>> buildQuery() {
    final fs.FirebaseFirestore delegate = _firestore.delegate;
    fs.Query<Map<String, Object?>> query = isCollectionGroupQuery
        ? delegate.collectionGroup(path)
        : delegate.collection(path);

    final List<dynamic> where = parameters['where'] as List<dynamic>? ?? [];
    for (final dynamic condition in where) {
      final List<dynamic> parts = condition as List<dynamic>;
      query = query.where(_filter(parts[0], parts[1] as String, parts[2]));
    }
    final Object? filters = parameters['filters'];
    if (filters != null) {
      query = query.where(_filterFromJson(filters as Map<dynamic, dynamic>));
    }

    final List<dynamic> orderBy = parameters['orderBy'] as List<dynamic>? ?? [];
    for (final dynamic order in orderBy) {
      final List<dynamic> parts = order as List<dynamic>;
      query = query.orderBy(
        ValueCodec.encodeField(parts[0]),
        descending: parts[1] == true,
      );
    }

    final Object? limit = parameters['limit'];
    if (limit != null) {
      query = query.limit(limit as int);
    }
    final Object? limitToLast = parameters['limitToLast'];
    if (limitToLast != null) {
      query = query.limitToLast(limitToLast as int);
    }

    List<Object?> values(Object cursor) => <Object?>[
      for (final Object? value in cursor as Iterable<dynamic>)
        ValueCodec.encode(value),
    ];
    final Object? startAt = parameters['startAt'];
    if (startAt != null) {
      query = query.startAt(values(startAt));
    }
    final Object? startAfter = parameters['startAfter'];
    if (startAfter != null) {
      query = query.startAfter(values(startAfter));
    }
    final Object? endAt = parameters['endAt'];
    if (endAt != null) {
      query = query.endAt(values(endAt));
    }
    final Object? endBefore = parameters['endBefore'];
    if (endBefore != null) {
      query = query.endBefore(values(endBefore));
    }
    return query;
  }

  static fs.Filter _filterFromJson(Map<dynamic, dynamic> json) {
    final Object? queries = json['queries'];
    if (queries != null) {
      final List<fs.Filter> filters = <fs.Filter>[
        for (final dynamic query in queries as List<dynamic>)
          _filterFromJson(query as Map<dynamic, dynamic>),
      ];
      return switch (json['op']) {
        'AND' => fs.Filter.and(filters),
        'OR' => fs.Filter.or(filters),
        final Object? op => throw ArgumentError.value(
          op,
          'op',
          'Unknown composite filter operator',
        ),
      };
    }
    return _filter(json['fieldPath'], json['op'] as String, json['value']);
  }

  static fs.Filter _filter(Object? field, String operator, Object? value) {
    final fs.FieldPath path = ValueCodec.encodeField(field);
    final Object? encoded = ValueCodec.encode(value);
    if (encoded == null) {
      // A null argument of Filter counts as not given, as in FlutterFire,
      // whose isNull: true and isNull: false arrive here as == and != null.
      return switch (operator) {
        '==' => fs.Filter(path, isNull: true),
        '!=' => fs.Filter(path, isNull: false),
        _ => throw ArgumentError.value(
          value,
          'value',
          'A "$operator" filter cannot compare with null',
        ),
      };
    }
    Iterable<Object?> list() => encoded as Iterable<Object?>;
    return switch (operator) {
      '==' => fs.Filter(path, isEqualTo: encoded),
      '!=' => fs.Filter(path, isNotEqualTo: encoded),
      '<' => fs.Filter(path, isLessThan: encoded),
      '<=' => fs.Filter(path, isLessThanOrEqualTo: encoded),
      '>' => fs.Filter(path, isGreaterThan: encoded),
      '>=' => fs.Filter(path, isGreaterThanOrEqualTo: encoded),
      'array-contains' => fs.Filter(path, arrayContains: encoded),
      'array-contains-any' => fs.Filter(path, arrayContainsAny: list()),
      'in' => fs.Filter(path, whereIn: list()),
      'not-in' => fs.Filter(path, whereNotIn: list()),
      _ => throw ArgumentError.value(operator, 'operator', 'Unknown operator'),
    };
  }

  @override
  QueryPlatform endAtDocument(List<dynamic> orders, List<dynamic> values) {
    return _copyWith(<String, dynamic>{
      'orderBy': orders,
      'endAt': values,
      'endBefore': null,
    });
  }

  @override
  QueryPlatform endAt(Iterable<dynamic> fields) {
    return _copyWith(<String, dynamic>{'endAt': fields, 'endBefore': null});
  }

  @override
  QueryPlatform endBeforeDocument(
    Iterable<dynamic> orders,
    Iterable<dynamic> values,
  ) {
    return _copyWith(<String, dynamic>{
      'orderBy': orders,
      'endAt': null,
      'endBefore': values,
    });
  }

  @override
  QueryPlatform endBefore(Iterable<dynamic> fields) {
    return _copyWith(<String, dynamic>{'endAt': null, 'endBefore': fields});
  }

  @override
  Future<QuerySnapshotPlatform> get([GetOptions options = const GetOptions()]) {
    return guard(() async {
      final fs.QuerySnapshot<Map<String, Object?>> snapshot = await buildQuery()
          .get(getOptionsOf(options));
      return querySnapshotOf(
        _firestore,
        snapshot,
        behavior: options.serverTimestampBehavior,
      );
    });
  }

  @override
  QueryPlatform limit(int limit) {
    return _copyWith(<String, dynamic>{'limit': limit, 'limitToLast': null});
  }

  @override
  QueryPlatform limitToLast(int limit) {
    return _copyWith(<String, dynamic>{'limit': null, 'limitToLast': limit});
  }

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) {
    return guardStream(
      _firestore.lazyStream(
        () => buildQuery().snapshots(
          includeMetadataChanges: includeMetadataChanges,
          source: listenSourceOf(listenSource),
        ),
      ),
    ).map(
      (fs.QuerySnapshot<Map<String, Object?>> snapshot) =>
          querySnapshotOf(_firestore, snapshot),
    );
  }

  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) {
    return _copyWith(<String, dynamic>{'orderBy': orders});
  }

  @override
  QueryPlatform startAfterDocument(List<dynamic> orders, List<dynamic> values) {
    return _copyWith(<String, dynamic>{
      'orderBy': orders,
      'startAt': null,
      'startAfter': values,
    });
  }

  @override
  QueryPlatform startAfter(Iterable<dynamic> fields) {
    return _copyWith(<String, dynamic>{'startAt': null, 'startAfter': fields});
  }

  @override
  QueryPlatform startAtDocument(
    Iterable<dynamic> orders,
    Iterable<dynamic> values,
  ) {
    return _copyWith(<String, dynamic>{
      'orderBy': orders,
      'startAt': values,
      'startAfter': null,
    });
  }

  @override
  QueryPlatform startAt(Iterable<dynamic> fields) {
    return _copyWith(<String, dynamic>{'startAt': fields, 'startAfter': null});
  }

  @override
  QueryPlatform where(List<List<dynamic>> conditions) {
    return _copyWith(<String, dynamic>{'where': conditions});
  }

  @override
  QueryPlatform whereFilter(FilterPlatformInterface filter) {
    final Object? existing = parameters['filters'];
    return _copyWith(<String, dynamic>{
      // Chained filters are combined with AND, as in the method channel
      // implementation and the native SDKs.
      'filters': existing == null
          ? filter.toJson()
          : <String, Object?>{
              'op': 'AND',
              'queries': <Object?>[existing, filter.toJson()],
            },
    });
  }

  @override
  AggregateQueryPlatform count() {
    return DartAggregateQuery(this, <Aggregation>[
      (type: AggregateType.count, field: null),
    ]);
  }

  @override
  AggregateQueryPlatform sum(String field) {
    return DartAggregateQuery(this, <Aggregation>[
      (type: AggregateType.sum, field: field),
    ]);
  }

  @override
  AggregateQueryPlatform average(String field) {
    return DartAggregateQuery(this, <Aggregation>[
      (type: AggregateType.average, field: field),
    ]);
  }

  @override
  AggregateQueryPlatform aggregate(
    pi.AggregateField aggregateField1, [
    pi.AggregateField? aggregateField2,
    pi.AggregateField? aggregateField3,
    pi.AggregateField? aggregateField4,
    pi.AggregateField? aggregateField5,
    pi.AggregateField? aggregateField6,
    pi.AggregateField? aggregateField7,
    pi.AggregateField? aggregateField8,
    pi.AggregateField? aggregateField9,
    pi.AggregateField? aggregateField10,
    pi.AggregateField? aggregateField11,
    pi.AggregateField? aggregateField12,
    pi.AggregateField? aggregateField13,
    pi.AggregateField? aggregateField14,
    pi.AggregateField? aggregateField15,
    pi.AggregateField? aggregateField16,
    pi.AggregateField? aggregateField17,
    pi.AggregateField? aggregateField18,
    pi.AggregateField? aggregateField19,
    pi.AggregateField? aggregateField20,
    pi.AggregateField? aggregateField21,
    pi.AggregateField? aggregateField22,
    pi.AggregateField? aggregateField23,
    pi.AggregateField? aggregateField24,
    pi.AggregateField? aggregateField25,
    pi.AggregateField? aggregateField26,
    pi.AggregateField? aggregateField27,
    pi.AggregateField? aggregateField28,
    pi.AggregateField? aggregateField29,
    pi.AggregateField? aggregateField30,
  ]) {
    final List<pi.AggregateField> fields = <pi.AggregateField?>[
      aggregateField1,
      aggregateField2,
      aggregateField3,
      aggregateField4,
      aggregateField5,
      aggregateField6,
      aggregateField7,
      aggregateField8,
      aggregateField9,
      aggregateField10,
      aggregateField11,
      aggregateField12,
      aggregateField13,
      aggregateField14,
      aggregateField15,
      aggregateField16,
      aggregateField17,
      aggregateField18,
      aggregateField19,
      aggregateField20,
      aggregateField21,
      aggregateField22,
      aggregateField23,
      aggregateField24,
      aggregateField25,
      aggregateField26,
      aggregateField27,
      aggregateField28,
      aggregateField29,
      aggregateField30,
    ].nonNulls.toList();
    return DartAggregateQuery(this, <Aggregation>[
      for (final pi.AggregateField field in fields)
        switch (field) {
          pi.count() => (type: AggregateType.count, field: null),
          pi.sum() => (type: AggregateType.sum, field: field.field),
          pi.average() => (type: AggregateType.average, field: field.field),
          _ => throw ArgumentError.value(
            field,
            'aggregateField',
            'Unsupported aggregate field ${field.runtimeType}',
          ),
        },
    ]);
  }

  @override
  bool operator ==(Object other) {
    return other is DartQuery &&
        other.runtimeType == runtimeType &&
        other.firestore == firestore &&
        other.path == path &&
        other.isCollectionGroupQuery == isCollectionGroupQuery &&
        const DeepCollectionEquality().equals(other.parameters, parameters);
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    firestore,
    path,
    isCollectionGroupQuery,
    const DeepCollectionEquality().hash(parameters),
  );
}
