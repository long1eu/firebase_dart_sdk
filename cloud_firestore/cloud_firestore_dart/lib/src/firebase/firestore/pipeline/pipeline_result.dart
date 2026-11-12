// Copyright 2026 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:meta/meta.dart';

/// One row produced by a pipeline.
///
/// A result is a document while the pipeline only filters, sorts and limits;
/// then [ref], [id], [createTime] and [updateTime] are set. After a stage that
/// builds new rows (`select`, `aggregate`, `distinct`, `unnest`, ...) a result
/// is a plain map and those are null.
///
/// Values of types this SDK has no class for yet (for example the BSON types
/// of Enterprise edition databases) are returned in their map encoding.
///
/// **Preview**: the Pipelines API is experimental and may change.
class PipelineResult {
  @internal
  PipelineResult(this._firestore, this._fields,
      {DocumentKey? key, this.createTime, this.updateTime})
      : _key = key;

  final Firestore _firestore;
  final ObjectValue _fields;
  final DocumentKey? _key;

  /// When the document was created, or null if this result is not a document.
  final Timestamp? createTime;

  /// When the document was last updated, or null if this result is not a
  /// document.
  final Timestamp? updateTime;

  /// The document this result was read from, or null if this result is not a
  /// document.
  DocumentReference<Map<String, Object?>>? get ref {
    final DocumentKey? key = _key;
    return key == null
        ? null
        : DocumentReference<Map<String, Object?>>(key, _firestore);
  }

  /// The id of the document, or null if this result is not a document.
  String? get id => _key?.path.last;

  /// All fields of this result.
  Map<String, Object?> data() => _convertObject(_fields);

  /// The value of [field], a dot-separated `String`, a [FieldPath] or a
  /// [Field]; null if the result has no such field.
  Object? get(Object field) {
    final model.FieldPath path;
    if (field is Field) {
      path = field.path;
    } else if (field is FieldPath) {
      path = field.internalPath;
    } else if (field is String) {
      path = FieldPath.fromDotSeparatedPath(field).internalPath;
    } else {
      throw ArgumentError(
          'A field must be a String, a FieldPath or a Field, but got: $field');
    }
    final FieldValue? value = _fields.get(path);
    return value == null ? null : _convertValue(value);
  }

  Object? _convertValue(FieldValue value) {
    if (value is ObjectValue) {
      return _convertObject(value);
    } else if (value is ArrayValue) {
      return value.internalValue.map(_convertValue).toList();
    } else if (value is ReferenceValue) {
      return DocumentReference<Map<String, Object?>>(value.value, _firestore);
    } else {
      return value.value;
    }
  }

  Map<String, Object?> _convertObject(ObjectValue value) {
    return <String, Object?>{
      for (final MapEntry<String, FieldValue> entry in value.internalValue)
        entry.key: _convertValue(entry.value),
    };
  }

  @override
  String toString() => 'PipelineResult{ref: ${_key?.path}, data: ${data()}}';
}

/// The results of executing a pipeline.
///
/// **Preview**: the Pipelines API is experimental and may change.
class PipelineSnapshot {
  @internal
  PipelineSnapshot(this.pipeline, List<PipelineResult> results,
      {this.executionTime})
      : results = List<PipelineResult>.unmodifiable(results);

  /// The pipeline that produced these results.
  final Pipeline pipeline;

  /// The results, in the order the server returned them.
  final List<PipelineResult> results;

  /// The time at which the results are valid. Null when the server did not
  /// report one.
  final Timestamp? executionTime;

  @override
  String toString() =>
      'PipelineSnapshot{executionTime: $executionTime, results: $results}';
}

/// Builds a snapshot from the responses of an `ExecutePipeline` call.
@internal
PipelineSnapshot decodePipelineResponses(
  Pipeline pipeline,
  Firestore firestore,
  RemoteSerializer serializer,
  List<proto.ExecutePipelineResponse> responses,
) {
  Timestamp? executionTime;
  final List<PipelineResult> results = <PipelineResult>[];
  for (final proto.ExecutePipelineResponse response in responses) {
    // Like the other SDKs, report the time of the first response.
    if (executionTime == null && response.hasExecutionTime()) {
      executionTime = serializer.decodeTimestamp(response.executionTime);
    }
    for (final proto.Document document in response.results) {
      results.add(PipelineResult(
        firestore,
        serializer.decodeMapFields(document.fields),
        key: document.name.isEmpty ? null : serializer.decodeKey(document.name),
        createTime: document.hasCreateTime()
            ? serializer.decodeTimestamp(document.createTime)
            : null,
        updateTime: document.hasUpdateTime()
            ? serializer.decodeTimestamp(document.updateTime)
            : null,
      ));
    }
  }
  return PipelineSnapshot(pipeline, results, executionTime: executionTime);
}
