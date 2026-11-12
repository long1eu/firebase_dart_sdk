// Copyright 2021 Google LLC
//
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// A JSON serializer to deserialize Firestore Bundles.
///
/// The bundle elements are the proto3 JSON (or ProtobufJS JSON) form of `BundleElement`. Values are first converted to
/// the equivalent protos and then to model objects with the [RemoteSerializer], so that documents loaded from a bundle
/// are identical to the ones received from the backend.
class BundleSerializer {
  const BundleSerializer(this.remoteSerializer);

  final RemoteSerializer remoteSerializer;

  /// Decodes a proto3 JSON `Value` into a model [FieldValue].
  FieldValue decodeValue(Map<String, dynamic> value) =>
      remoteSerializer.decodeValue(_decodeValue(value));

  NamedQuery decodeNamedQuery(Map<String, dynamic> namedQuery) {
    final String name = _getString(namedQuery, 'name');
    final BundledQuery bundledQuery =
        _decodeBundledQuery(_getObject(namedQuery, 'bundledQuery'));
    final SnapshotVersion readTime =
        _decodeSnapshotVersion(_get(namedQuery, 'readTime'));
    return NamedQuery(name, bundledQuery, readTime);
  }

  BundleMetadata decodeBundleMetadata(Map<String, dynamic> bundleMetadata) {
    final String bundleId = _getString(bundleMetadata, 'id');
    final int version = _asInt(_get(bundleMetadata, 'version'));
    final SnapshotVersion createTime =
        _decodeSnapshotVersion(_get(bundleMetadata, 'createTime'));
    final int totalDocuments = _asInt(_get(bundleMetadata, 'totalDocuments'));
    final int totalBytes = _asInt(_get(bundleMetadata, 'totalBytes'));
    return BundleMetadata(
        bundleId, version, createTime, totalDocuments, totalBytes);
  }

  BundledDocumentMetadata decodeBundledDocumentMetadata(
      Map<String, dynamic> bundledDocumentMetadata) {
    final DocumentKey key = DocumentKey.fromPath(
        _decodeName(_getString(bundledDocumentMetadata, 'name')));
    final SnapshotVersion readTime =
        _decodeSnapshotVersion(_get(bundledDocumentMetadata, 'readTime'));
    final bool exists = _optBool(bundledDocumentMetadata, 'exists', false);
    final List<String> queries = <String>[];
    // Technically, the queries array should never be missing, but we treat a missing and empty array the same to avoid
    // crashing during data import.
    final dynamic queriesJson = bundledDocumentMetadata['queries'];
    if (queriesJson is List<dynamic>) {
      for (final dynamic query in queriesJson) {
        queries.add(query as String);
      }
    }
    return BundledDocumentMetadata(key, readTime, exists, queries);
  }

  BundleDocument decodeDocument(Map<String, dynamic> document) {
    final String name = _getString(document, 'name');
    final DocumentKey key = DocumentKey.fromPath(_decodeName(name));
    final SnapshotVersion updateTime =
        _decodeSnapshotVersion(_get(document, 'updateTime'));

    final proto.Document documentProto = proto.Document.create()
      ..name = remoteSerializer.encodeKey(key)
      ..updateTime = remoteSerializer.encodeVersion(updateTime);
    final Map<String, dynamic>? fields = _optObject(document, 'fields');
    if (fields != null) {
      for (final MapEntry<String, dynamic> entry in fields.entries) {
        documentProto.fields[entry.key] = _decodeValue(_asObject(entry.value));
      }
    }

    return BundleDocument(Document.fromProto(
      key,
      updateTime,
      DocumentState.synced,
      documentProto..freeze(),
      remoteSerializer.decodeValue,
    ));
  }

  // Names

  ResourcePath _decodeName(String name) {
    final ResourcePath resourcePath = ResourcePath.fromString(name);
    if (!_isLocalResourceName(resourcePath)) {
      throw ArgumentError(
          'Resource name is not valid for current instance: $name');
    }
    return resourcePath.popFirst(5);
  }

  /// Validates that a path has a prefix that belongs to the current database. (Android:
  /// `RemoteSerializer.isLocalResourceName`.)
  bool _isLocalResourceName(ResourcePath path) {
    return path.length >= 5 &&
        path[0] == 'projects' &&
        path[2] == 'databases' &&
        path[4] == 'documents' &&
        path[1] == remoteSerializer.databaseId.projectId &&
        path[3] == remoteSerializer.databaseId.databaseId;
  }

  // Queries

  BundledQuery _decodeBundledQuery(Map<String, dynamic> bundledQuery) {
    final Map<String, dynamic> structuredQuery =
        _getObject(bundledQuery, 'structuredQuery');
    _verifyNoSelect(structuredQuery);

    ResourcePath parent = _decodeName(_getString(bundledQuery, 'parent'));
    final List<dynamic> from = _getArray(structuredQuery, 'from');
    _verifyCollectionSelector(from);
    final Map<String, dynamic> collectionSelector = _asObject(from[0]);
    final bool allDescendants =
        _optBool(collectionSelector, 'allDescendants', false);
    String? collectionGroup;
    if (allDescendants) {
      collectionGroup = _getString(collectionSelector, 'collectionId');
    } else {
      parent =
          parent.appendSegment(_getString(collectionSelector, 'collectionId'));
    }

    final List<Filter> filters =
        _decodeWhere(_optObject(structuredQuery, 'where'));
    final List<OrderBy> orderBys =
        _decodeOrderBy(_optArray(structuredQuery, 'orderBy'));
    final Bound? startAt = _decodeBound(_optObject(structuredQuery, 'startAt'));
    final Bound? endAt = _decodeBound(_optObject(structuredQuery, 'endAt'));

    _verifyNoOffset(structuredQuery);
    final int limit = _decodeLimit(structuredQuery);
    final BundledQueryLimitType limitType = _decodeLimitType(bundledQuery);

    return BundledQuery(
      Query(
        parent,
        collectionGroup: collectionGroup,
        filters: filters,
        explicitSortOrder: orderBys,
        limit: limit,
        startAt: startAt,
        endAt: endAt,
      ),
      limitType,
    );
  }

  int _decodeLimit(Map<String, dynamic> structuredQuery) {
    final dynamic limit = structuredQuery['limit'];
    if (limit is Map<String, dynamic>) {
      // ProtobufJS
      return _optInt(limit, 'value', Query.noLimit);
    } else {
      // Proto3 JSON
      return _optInt(structuredQuery, 'limit', Query.noLimit);
    }
  }

  Bound? _decodeBound(Map<String, dynamic>? bound) {
    if (bound == null) {
      return null;
    }

    final List<FieldValue> cursor = <FieldValue>[];
    final bool before = _optBool(bound, 'before', false);
    final List<dynamic>? values = _optArray(bound, 'values');
    if (values != null) {
      for (final dynamic value in values) {
        cursor
            .add(remoteSerializer.decodeValue(_decodeValue(_asObject(value))));
      }
    }
    return Bound(position: cursor, before: before);
  }

  List<OrderBy> _decodeOrderBy(List<dynamic>? orderBys) {
    final List<OrderBy> result = <OrderBy>[];
    if (orderBys != null) {
      for (final dynamic entry in orderBys) {
        final Map<String, dynamic> orderBy = _asObject(entry);
        final FieldPath fieldPath =
            _decodeFieldReference(_getObject(orderBy, 'field'));
        final String directionString =
            _optString(orderBy, 'direction', 'ASCENDING');
        final OrderByDirection direction = directionString == 'ASCENDING'
            ? OrderByDirection.ascending
            : OrderByDirection.descending;
        result.add(OrderBy.getInstance(direction, fieldPath));
      }
    }
    return result;
  }

  List<Filter> _decodeWhere(Map<String, dynamic>? where) {
    final List<Filter> result = <Filter>[];
    if (where != null) {
      _decodeFilter(result, where);
    }
    return result;
  }

  void _decodeFilter(List<Filter> result, Map<String, dynamic> filter) {
    if (filter.containsKey('compositeFilter')) {
      _decodeCompositeFilter(result, _getObject(filter, 'compositeFilter'));
    } else if (filter.containsKey('fieldFilter')) {
      _decodeFieldFilter(result, _getObject(filter, 'fieldFilter'));
    } else if (filter.containsKey('unaryFilter')) {
      _decodeUnaryFilter(result, _getObject(filter, 'unaryFilter'));
    }
  }

  void _decodeCompositeFilter(
      List<Filter> result, Map<String, dynamic> compositeFilter) {
    if (_getString(compositeFilter, 'op') != 'AND') {
      throw ArgumentError(
          'The Dart SDK only supports composite filters of type \'AND\'');
    }

    final List<dynamic>? filters = _optArray(compositeFilter, 'filters');
    if (filters != null) {
      for (final dynamic filter in filters) {
        _decodeFilter(result, _asObject(filter));
      }
    }
  }

  void _decodeFieldFilter(
      List<Filter> result, Map<String, dynamic> fieldFilter) {
    final FieldPath fieldPath =
        _decodeFieldReference(_getObject(fieldFilter, 'field'));
    final FilterOperator filterOperator =
        _decodeFieldFilterOperator(_getString(fieldFilter, 'op'));
    result.add(FieldFilter(
      fieldPath,
      filterOperator,
      remoteSerializer
          .decodeValue(_decodeValue(_getObject(fieldFilter, 'value'))),
    ));
  }

  void _decodeUnaryFilter(
      List<Filter> result, Map<String, dynamic> unaryFilter) {
    final FieldPath fieldPath =
        _decodeFieldReference(_getObject(unaryFilter, 'field'));
    final String operator = _getString(unaryFilter, 'op');

    switch (operator) {
      case 'IS_NAN':
        result
            .add(FieldFilter(fieldPath, FilterOperator.equal, DoubleValue.nan));
        break;
      case 'IS_NULL':
        result.add(FieldFilter(
            fieldPath, FilterOperator.equal, NullValue.nullValue()));
        break;
      case 'IS_NOT_NAN':
        result.add(
            FieldFilter(fieldPath, FilterOperator.notEqual, DoubleValue.nan));
        break;
      case 'IS_NOT_NULL':
        result.add(FieldFilter(
            fieldPath, FilterOperator.notEqual, NullValue.nullValue()));
        break;
      default:
        throw ArgumentError('Unexpected unary filter: $operator');
    }
  }

  FilterOperator _decodeFieldFilterOperator(String operator) {
    switch (operator) {
      case 'LESS_THAN':
        return FilterOperator.lessThan;
      case 'LESS_THAN_OR_EQUAL':
        return FilterOperator.lessThanOrEqual;
      case 'GREATER_THAN':
        return FilterOperator.graterThan;
      case 'GREATER_THAN_OR_EQUAL':
        return FilterOperator.graterThanOrEqual;
      case 'EQUAL':
        return FilterOperator.equal;
      case 'NOT_EQUAL':
        return FilterOperator.notEqual;
      case 'ARRAY_CONTAINS':
        return FilterOperator.arrayContains;
      case 'ARRAY_CONTAINS_ANY':
        return FilterOperator.arrayContainsAny;
      case 'IN':
        return FilterOperator.IN;
      case 'NOT_IN':
        return FilterOperator.NOT_IN;
      default:
        throw ArgumentError('Unexpected field filter operator: $operator');
    }
  }

  FieldPath _decodeFieldReference(Map<String, dynamic> fieldReference) {
    return FieldPath.fromServerFormat(_getString(fieldReference, 'fieldPath'));
  }

  BundledQueryLimitType _decodeLimitType(Map<String, dynamic> bundledQuery) {
    final String limitType = _optString(bundledQuery, 'limitType', 'FIRST');
    if (limitType == 'FIRST') {
      return BundledQueryLimitType.first;
    } else if (limitType == 'LAST') {
      return BundledQueryLimitType.last;
    } else {
      throw ArgumentError('Invalid limit type for bundle query: $limitType');
    }
  }

  void _verifyCollectionSelector(List<dynamic> from) {
    if (from.length != 1) {
      throw ArgumentError(
          'Only queries with a single \'from\' clause are supported by the Dart SDK');
    }
  }

  void _verifyNoOffset(Map<String, dynamic> structuredQuery) {
    if (structuredQuery.containsKey('offset')) {
      throw ArgumentError(
          'Queries with offsets are not supported by the Dart SDK');
    }
  }

  void _verifyNoSelect(Map<String, dynamic> structuredQuery) {
    if (structuredQuery.containsKey('select')) {
      throw ArgumentError(
          'Queries with \'select\' statements are not supported by the Dart SDK');
    }
  }

  // Values

  proto_v1.Value _decodeValue(Map<String, dynamic> value) {
    final proto_v1.Value builder = proto_v1.Value.create();

    if (value.containsKey('nullValue')) {
      builder.nullValue = proto.NullValue.NULL_VALUE;
    } else if (value.containsKey('booleanValue')) {
      builder.booleanValue = _optBool(value, 'booleanValue', false);
    } else if (value.containsKey('integerValue')) {
      builder.integerValue = Int64(_asInt(value['integerValue']));
    } else if (value.containsKey('doubleValue')) {
      builder.doubleValue = _asDouble(value['doubleValue']);
    } else if (value.containsKey('timestampValue')) {
      builder.timestampValue =
          _encodeTimestamp(_decodeTimestamp(value['timestampValue']));
    } else if (value.containsKey('stringValue')) {
      builder.stringValue = _optString(value, 'stringValue', '');
    } else if (value.containsKey('bytesValue')) {
      builder.bytesValue = _decodeBytes(_getString(value, 'bytesValue'));
    } else if (value.containsKey('referenceValue')) {
      builder.referenceValue = _getString(value, 'referenceValue');
    } else if (value.containsKey('geoPointValue')) {
      final Map<String, dynamic> geoPoint = _getObject(value, 'geoPointValue');
      builder.geoPointValue = proto.LatLng.create()
        ..latitude = _optDouble(geoPoint, 'latitude', 0)
        ..longitude = _optDouble(geoPoint, 'longitude', 0);
    } else if (value.containsKey('arrayValue')) {
      final proto.ArrayValue array = proto.ArrayValue.create();
      final List<dynamic>? values =
          _optArray(_getObject(value, 'arrayValue'), 'values');
      if (values != null) {
        for (final dynamic element in values) {
          array.values.add(_decodeValue(_asObject(element)));
        }
      }
      builder.arrayValue = array;
    } else if (value.containsKey('mapValue')) {
      final proto.MapValue map = proto.MapValue.create();
      final Map<String, dynamic>? fields =
          _optObject(_getObject(value, 'mapValue'), 'fields');
      if (fields != null) {
        for (final MapEntry<String, dynamic> entry in fields.entries) {
          map.fields[entry.key] = _decodeValue(_asObject(entry.value));
        }
      }
      builder.mapValue = map;
    } else {
      throw ArgumentError('Unexpected value type: $value');
    }

    return builder;
  }

  Uint8List _decodeBytes(String encoded) {
    return base64.decode(encoded.replaceAll(RegExp(r'\s'), ''));
  }

  // Timestamps

  SnapshotVersion _decodeSnapshotVersion(dynamic timestamp) {
    return SnapshotVersion(_decodeTimestamp(timestamp));
  }

  proto.Timestamp _encodeTimestamp(Timestamp timestamp) {
    return remoteSerializer.encodeTimestamp(timestamp);
  }

  Timestamp _decodeTimestamp(dynamic timestamp) {
    if (timestamp is String) {
      return _decodeTimestampString(timestamp);
    } else if (timestamp is Map<String, dynamic>) {
      return Timestamp(
        _optInt(timestamp, 'seconds', 0),
        _optInt(timestamp, 'nanos', 0),
      );
    } else {
      throw ArgumentError(
          'Timestamps must be either ISO 8601-formatted strings or JSON objects');
    }
  }

  static final RegExp _timestampPattern = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d*))?(Z|[+-]\d+:\d+)$');

  /// Parses an RFC 3339 timestamp such as `2021-01-01T10:20:30.123456789Z` or `2021-01-01T10:20:30+01:00`, using the
  /// proleptic Gregorian calendar. Only the first nine fractional digits are used.
  Timestamp _decodeTimestampString(String timestamp) {
    final RegExpMatch? match = _timestampPattern.firstMatch(timestamp);
    if (match == null) {
      throw ArgumentError('Invalid timestamp: $timestamp');
    }

    final int year = int.parse(match.group(1)!);
    final int month = int.parse(match.group(2)!);
    final int day = int.parse(match.group(3)!);
    final int hour = int.parse(match.group(4)!);
    final int minute = int.parse(match.group(5)!);
    final int second = int.parse(match.group(6)!);
    int seconds = DateTime.utc(year, month, day, hour, minute, second)
            .millisecondsSinceEpoch ~/
        1000;

    int nanos = 0;
    final String fraction = match.group(7) ?? '';
    for (int i = 0; i < 9; i++) {
      nanos *= 10;
      if (i < fraction.length) {
        nanos += fraction.codeUnitAt(i) - 0x30;
      }
    }

    final String offset = match.group(8)!;
    if (offset != 'Z') {
      final List<String> parts = offset.substring(1).split(':');
      final int offsetSeconds =
          (int.parse(parts[0]) * 60 + int.parse(parts[1])) * 60;
      if (offset.startsWith('+')) {
        seconds -= offsetSeconds;
      } else {
        seconds += offsetSeconds;
      }
    }
    return Timestamp(seconds, nanos);
  }

  // JSON helpers (the Android SDK uses org.json, whose getXxx/optXxx coerce between strings and numbers).

  dynamic _get(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key)) {
      throw ArgumentError('Missing field \'$key\' in $json');
    }
    return json[key];
  }

  String _getString(Map<String, dynamic> json, String key) {
    final dynamic value = _get(json, key);
    if (value is String) {
      return value;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    throw ArgumentError('Field \'$key\' is not a string: $value');
  }

  Map<String, dynamic> _getObject(Map<String, dynamic> json, String key) {
    return _asObject(_get(json, key));
  }

  List<dynamic> _getArray(Map<String, dynamic> json, String key) {
    final dynamic value = _get(json, key);
    if (value is List<dynamic>) {
      return value;
    }
    throw ArgumentError('Field \'$key\' is not an array: $value');
  }

  Map<String, dynamic>? _optObject(Map<String, dynamic> json, String key) {
    final dynamic value = json[key];
    return value is Map<String, dynamic> ? value : null;
  }

  List<dynamic>? _optArray(Map<String, dynamic> json, String key) {
    final dynamic value = json[key];
    return value is List<dynamic> ? value : null;
  }

  String _optString(Map<String, dynamic> json, String key, String fallback) {
    final dynamic value = json[key];
    if (value is String) {
      return value;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return fallback;
  }

  bool _optBool(Map<String, dynamic> json, String key, bool fallback) {
    final dynamic value = json[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      if (value.toLowerCase() == 'true') {
        return true;
      }
      if (value.toLowerCase() == 'false') {
        return false;
      }
    }
    return fallback;
  }

  int _optInt(Map<String, dynamic> json, String key, int fallback) {
    final dynamic value = json[key];
    final int? result = _tryInt(value);
    return result ?? fallback;
  }

  double _optDouble(Map<String, dynamic> json, String key, double fallback) {
    final dynamic value = json[key];
    final double? result = _tryDouble(value);
    return result ?? fallback;
  }

  Map<String, dynamic> _asObject(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    throw ArgumentError('Expected a JSON object but got: $value');
  }

  int _asInt(dynamic value) {
    final int? result = _tryInt(value);
    if (result == null) {
      throw ArgumentError('Expected an integer but got: $value');
    }
    return result;
  }

  double _asDouble(dynamic value) {
    final double? result = _tryDouble(value);
    if (result == null) {
      throw ArgumentError('Expected a number but got: $value');
    }
    return result;
  }

  int? _tryInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? double.tryParse(value)?.toInt();
    }
    return null;
  }

  double? _tryDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      // Proto3 JSON encodes NaN and the infinities as the strings 'NaN', 'Infinity' and '-Infinity'.
      return double.tryParse(value);
    }
    return null;
  }
}
