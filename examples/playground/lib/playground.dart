/// The parts of the playground that do not touch the page: how the instance
/// is opened, the query the form describes, and how values are shown.
///
/// The page (`web/main.dart`) and the smoke test (`test/`) both use it.
library;

import 'dart:convert';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

/// Options with a `demo-` project id: no Firebase project is behind them, and
/// the client never sends a request with them (see [openOffline]).
const FirebaseOptions playgroundOptions = FirebaseOptions(
  apiKey: 'demo-key',
  applicationId: '1:1234567890:web:playground',
  projectId: 'demo-playground',
);

/// The two collections the page offers.
const List<String> playgroundCollections = <String>['cities', 'tasks'];

/// Opens an instance on a memory cache and disables its network before
/// anything else is queued.
///
/// The client starts its network on its own queue when it is created, but it
/// opens a stream only for a listener or a pending write. Both are queued
/// behind [Firestore.disableNetwork] here, so no stream is ever opened and no
/// request is ever made. A memory cache starts empty, so there is no pending
/// write from an earlier visit that the start could try to send.
Future<Firestore> openOffline(FirebaseApp app) async {
  final Firestore firestore = Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings().copyWith(
      cacheSettings: const MemoryCacheSettings(),
    ),
  );
  await firestore.disableNetwork();
  return firestore;
}

/// The operators of the where clause of the form.
enum WhereOp {
  none('(none)'),
  isEqualTo('=='),
  isNotEqualTo('!='),
  isLessThan('<'),
  isLessThanOrEqualTo('<='),
  isGreaterThan('>'),
  isGreaterThanOrEqualTo('>='),
  arrayContains('array-contains');

  const WhereOp(this.symbol);

  /// What the select of the form shows.
  final String symbol;
}

/// The query of the form: a collection, at most one where clause, at most one
/// orderBy and a limit.
class QuerySpec {
  const QuerySpec({
    required this.collection,
    this.whereField = '',
    this.op = WhereOp.none,
    this.whereValue = '',
    this.orderField = '',
    this.descending = false,
    this.limit,
  });

  final String collection;
  final String whereField;
  final WhereOp op;

  /// The value as typed: JSON (`3`, `true`, `"Paris"`, `null`), or a string.
  final String whereValue;
  final String orderField;
  final bool descending;
  final int? limit;

  bool get _hasWhere => op != WhereOp.none && whereField.isNotEmpty;

  /// The query on [firestore]. Throws what the client throws for a query it
  /// does not accept (an [ArgumentError] for an invalid field, for example).
  Query<Map<String, Object?>> build(Firestore firestore) {
    Query<Map<String, Object?>> query = firestore.collection(collection);
    if (_hasWhere) {
      final Object? value = parseValue(whereValue);
      query = switch (op) {
        WhereOp.none => query,
        WhereOp.isEqualTo => query.where(whereField, isEqualTo: value),
        WhereOp.isNotEqualTo => query.where(whereField, isNotEqualTo: value),
        WhereOp.isLessThan => query.where(whereField, isLessThan: value),
        WhereOp.isLessThanOrEqualTo => query.where(
          whereField,
          isLessThanOrEqualTo: value,
        ),
        WhereOp.isGreaterThan => query.where(whereField, isGreaterThan: value),
        WhereOp.isGreaterThanOrEqualTo => query.where(
          whereField,
          isGreaterThanOrEqualTo: value,
        ),
        WhereOp.arrayContains => query.where(whereField, arrayContains: value),
      };
    }
    if (orderField.isNotEmpty) {
      query = query.orderBy(
        orderField,
        descending ? Direction.descending : Direction.ascending,
      );
    }
    final int? max = limit;
    if (max != null) {
      query = query.limit(max);
    }
    return query;
  }

  /// The Dart code of the listener, as the page shows it.
  String toDart() {
    final StringBuffer code = StringBuffer(
      "firestore\n    .collection('$collection')",
    );
    if (_hasWhere) {
      code.write(
        "\n    .where('$whereField', ${op.name}: "
        '${_dartLiteral(parseValue(whereValue))})',
      );
    }
    if (orderField.isNotEmpty) {
      code.write(
        "\n    .orderBy('$orderField'"
        '${descending ? ', Direction.descending' : ''})',
      );
    }
    if (limit != null) {
      code.write('\n    .limit($limit)');
    }
    code.write(
      '\n    .getSnapshots(MetadataChanges.include)\n    .listen(...);',
    );
    return code.toString();
  }
}

/// [text] read as JSON when it is valid JSON, as a string otherwise: `3` is a
/// number, `true` a bool, `Paris` and `"Paris"` the same string.
Object? parseValue(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  try {
    return jsonDecode(trimmed);
  } on FormatException {
    return trimmed;
  }
}

String _dartLiteral(Object? value) => switch (value) {
  final String text => "'${text.replaceAll("'", r"\'")}'",
  _ => jsonEncode(value),
};

/// [value] as short JSON. A [Timestamp] is shown as an ISO 8601 time.
String formatValue(Object? value) => jsonEncode(value, toEncodable: _encodable);

/// [data] as indented JSON, for the edit form. The values the page sets itself
/// ([updatedAtField]) are left out.
String formatDocument(Map<String, Object?> data) {
  final Map<String, Object?> editable = <String, Object?>{
    for (final MapEntry<String, Object?> entry in data.entries)
      if (entry.key != updatedAtField) entry.key: entry.value,
  };
  return const JsonEncoder.withIndent('  ', _encodable).convert(editable);
}

Object? _encodable(Object? value) => switch (value) {
  final Timestamp time => time.toDate().toUtc().toIso8601String(),
  _ => value.toString(),
};

/// The field each write of the page sets to [FieldValue.serverTimestamp].
const String updatedAtField = 'updatedAt';

/// The documents that "Add sample data" writes, in one batch.
const Map<String, Map<String, Object?>> sampleDocuments =
    <String, Map<String, Object?>>{
      'cities/paris': <String, Object?>{
        'name': 'Paris',
        'country': 'FR',
        'population': 2102650,
        'capital': true,
      },
      'cities/lyon': <String, Object?>{
        'name': 'Lyon',
        'country': 'FR',
        'population': 520774,
        'capital': false,
      },
      'cities/tokyo': <String, Object?>{
        'name': 'Tokyo',
        'country': 'JP',
        'population': 14094034,
        'capital': true,
      },
      'cities/osaka': <String, Object?>{
        'name': 'Osaka',
        'country': 'JP',
        'population': 2752412,
        'capital': false,
      },
      'tasks/write-docs': <String, Object?>{
        'title': 'Write the docs',
        'priority': 2,
        'done': false,
        'tags': <String>['docs'],
      },
      'tasks/fix-bug': <String, Object?>{
        'title': 'Fix the bug',
        'priority': 1,
        'done': false,
        'tags': <String>['code', 'urgent'],
      },
      'tasks/ship': <String, Object?>{
        'title': 'Ship it',
        'priority': 3,
        'done': true,
        'tags': <String>['code'],
      },
    };
