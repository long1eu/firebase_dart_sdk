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

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/query_to_pipeline.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/stage.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:meta/meta.dart';

/// Chooses where a [Pipeline] reads its input from. Get one with
/// `firestore.pipeline()`.
///
/// **Preview**: the Pipelines API is experimental and may change.
class PipelineSource {
  @internal
  PipelineSource(this._firestore);

  final Firestore _firestore;

  /// Reads the documents of one collection: a slash-separated path
  /// (`String`) or a [CollectionReference].
  ///
  /// With [forceIndex] the server uses the index with that name.
  Pipeline collection(Object collection,
      {String? forceIndex, Map<String, Object?>? rawOptions}) {
    final String path;
    if (collection is CollectionReference) {
      _validateDatabase(collection.firestore.databaseId, 'CollectionReference');
      path = collection.path;
    } else if (collection is String) {
      path = collection;
    } else {
      throw ArgumentError(
          'collection() takes a path or a CollectionReference, but got: '
          '$collection');
    }
    final ResourcePath resourcePath = _parsePath(path, 'collection');
    if (resourcePath.length.isEven) {
      throw ArgumentError(
          'Invalid collection path ($path). A collection path must have an '
          'odd number of segments.');
    }
    return _start(Stage(
      'collection',
      args: <pb.Value Function(PipelineEncoder)>[
        (_) => relativeReferenceValue(resourcePath.canonicalString),
      ],
      options: _forceIndex(forceIndex),
      rawOptions: rawOptions,
    ));
  }

  /// Reads the documents of every collection with the id [collectionId],
  /// wherever it is in the database.
  Pipeline collectionGroup(String collectionId,
      {String? forceIndex, Map<String, Object?>? rawOptions}) {
    if (collectionId.isEmpty || collectionId.contains('/')) {
      throw ArgumentError(
          "Invalid collection id '$collectionId'. A collection id must not be "
          "empty and must not contain '/'.");
    }
    return _start(Stage(
      'collection_group',
      args: <pb.Value Function(PipelineEncoder)>[
        (_) => pb.Value()..referenceValue = '',
        (_) => stringValue(collectionId),
      ],
      options: _forceIndex(forceIndex),
      rawOptions: rawOptions,
    ));
  }

  /// Reads every document of the database.
  Pipeline database({Map<String, Object?>? rawOptions}) {
    return _start(Stage('database', rawOptions: rawOptions));
  }

  /// Reads the given documents: slash-separated paths (`String`) or
  /// [DocumentReference]s.
  Pipeline documents(List<Object> documents,
      {Map<String, Object?>? rawOptions}) {
    if (documents.isEmpty) {
      throw ArgumentError('documents() needs at least one document.');
    }
    final List<String> paths = <String>[];
    for (final Object document in documents) {
      final String path;
      if (document is DocumentReference) {
        _validateDatabase(document.firestore.databaseId, 'DocumentReference');
        path = document.path;
      } else if (document is String) {
        path = document;
      } else {
        throw ArgumentError(
            'documents() takes paths and DocumentReferences, but got: '
            '$document');
      }
      final ResourcePath resourcePath = _parsePath(path, 'documents');
      if (resourcePath.length.isOdd) {
        throw ArgumentError(
            'Invalid document path ($path). A document path must have an even '
            'number of segments.');
      }
      paths.add(resourcePath.canonicalString);
    }
    return _start(Stage(
      'documents',
      args: <pb.Value Function(PipelineEncoder)>[
        for (final String path in paths) (_) => relativeReferenceValue(path),
      ],
      rawOptions: rawOptions,
    ));
  }

  /// Uses the given maps as the input, without reading the database. Values
  /// may be [Expression]s, also inside nested maps and lists.
  Pipeline literals(List<Map<String, Object?>> documents,
      {Map<String, Object?>? rawOptions}) {
    final List<Map<String, Expression>> encoded = documents
        .map((Map<String, Object?> document) => <String, Expression>{
              for (final MapEntry<String, Object?> entry in document.entries)
                entry.key: toExpression(entry.value),
            })
        .toList(growable: false);
    return _start(Stage(
      'literals',
      args: <pb.Value Function(PipelineEncoder)>[
        for (final Map<String, Expression> document in encoded)
          (PipelineEncoder encoder) => encodeExpressionMap(encoder, document),
      ],
      rawOptions: rawOptions,
    ));
  }

  /// Reads the documents of the subcollection [path] of the document that an
  /// enclosing pipeline is processing.
  ///
  /// The returned pipeline cannot be executed on its own; use it as a
  /// subquery, with [Pipeline.toArrayExpression] or
  /// [Pipeline.toScalarExpression]:
  ///
  /// ```dart
  /// firestore.pipeline().collection('books').addFields([
  ///   firestore.pipeline().subcollection('reviews')
  ///       .select(['stars']).toArrayExpression().as('stars'),
  /// ]);
  /// ```
  Pipeline subcollection(String path, {Map<String, Object?>? rawOptions}) {
    final ResourcePath resourcePath = _parsePath(path, 'subcollection');
    if (resourcePath.length.isEven) {
      throw ArgumentError(
          'Invalid subcollection path ($path). A collection path must have '
          'an odd number of segments.');
    }
    return _start(Stage(
      'subcollection',
      args: <pb.Value Function(PipelineEncoder)>[
        (_) => stringValue(resourcePath.canonicalString),
      ],
      rawOptions: rawOptions,
    ));
  }

  /// Creates the pipeline that returns the same documents, in the same
  /// order, as the classic [query].
  Pipeline createFrom(Query<Object?> query) {
    _validateDatabase(query.firestore.databaseId, 'Query');
    return queryToPipeline(_firestore, query.query);
  }

  /// Creates the pipeline that computes the aggregations of the classic
  /// [aggregateQuery] (`query.count()`, `query.aggregate(...)`).
  ///
  /// The single result has one field per aggregation, named after the alias
  /// given to `aggregateWithAliases`, or `count`, `sum_<field>` and
  /// `average_<field>` without aliases.
  Pipeline createFromAggregateQuery(AggregateQuery aggregateQuery) {
    final Map<String, AggregateField> fields = aggregateQuery.aliases ??
        <String, AggregateField>{
          for (final AggregateField field in aggregateQuery.aggregateFields)
            field.alias: field,
        };
    AggregateFunction convert(AggregateField aggregate) {
      if (aggregate is CountAggregateField) {
        return AggregateFunction('count');
      }
      final Field field =
          Field(model.FieldPath.fromServerFormat(aggregate.fieldPath));
      return aggregate is SumAggregateField ? field.sum() : field.average();
    }

    return createFrom(aggregateQuery.query).aggregate(<AliasedAggregate>[
      for (final MapEntry<String, AggregateField> entry in fields.entries)
        // The server reads an alias as a field path; this keeps a name with
        // dots or other special characters one field.
        convert(entry.value)
            .as(model.FieldPath.fromSingleSegment(entry.key).canonicalString),
    ]);
  }

  /// Creates the pipeline that returns the same documents, nearest first, as
  /// the classic vector query [vectorQuery] (`query.findNearest(...)`).
  ///
  /// A `distanceThreshold` becomes a filter that computes the distance again
  /// with the matching distance function.
  Pipeline createFromVectorQuery(VectorQuery vectorQuery) {
    final Field vectorField = Field(vectorQuery.vectorField);
    Pipeline pipeline = createFrom(vectorQuery.query).findNearest(
      vectorField,
      vectorQuery.queryVector,
      vectorQuery.distanceMeasure,
      limit: vectorQuery.limit,
      distanceField: vectorQuery.distanceResultField,
    );
    final double? threshold = vectorQuery.distanceThreshold;
    if (threshold != null) {
      final VectorValue vector = vectorQuery.queryVector;
      switch (vectorQuery.distanceMeasure) {
        case DistanceMeasure.euclidean:
          pipeline = pipeline.where(
              vectorField.euclideanDistance(vector).lessThanOrEqual(threshold));
          break;
        case DistanceMeasure.cosine:
          pipeline = pipeline.where(
              vectorField.cosineDistance(vector).lessThanOrEqual(threshold));
          break;
        case DistanceMeasure.dotProduct:
          // A larger dot product means more similar.
          pipeline = pipeline.where(
              vectorField.dotProduct(vector).greaterThanOrEqual(threshold));
          break;
      }
    }
    return pipeline;
  }

  Pipeline _start(Stage stage) => Pipeline(_firestore, <Stage>[stage]);

  static Map<String, pb.Value Function(PipelineEncoder)> _forceIndex(
      String? forceIndex) {
    return <String, pb.Value Function(PipelineEncoder)>{
      if (forceIndex != null) 'force_index': (_) => stringValue(forceIndex),
    };
  }

  /// Resolves the `collection` argument of the `insert` and `upsert` stages
  /// to a path relative to the database root.
  @internal
  static String collectionPath(
      Firestore firestore, Object collection, String method) {
    final String path;
    if (collection is CollectionReference) {
      PipelineSource(firestore)._validateDatabase(
          collection.firestore.databaseId, 'CollectionReference');
      path = collection.path;
    } else if (collection is String) {
      path = collection;
    } else {
      throw ArgumentError(
          '$method() takes a path or a CollectionReference as the '
          'collection, but got: $collection');
    }
    final ResourcePath resourcePath = _parsePath(path, method);
    if (resourcePath.length.isEven) {
      throw ArgumentError(
          'Invalid collection path ($path). A collection path must have an '
          'odd number of segments.');
    }
    return resourcePath.canonicalString;
  }

  static ResourcePath _parsePath(String path, String method) {
    if (path.contains('//')) {
      throw ArgumentError(
          'Invalid path ($path). Paths must not contain // in them.');
    }
    final ResourcePath resourcePath = ResourcePath.fromString(path);
    if (resourcePath.isEmpty) {
      throw ArgumentError('$method() needs a non-empty path.');
    }
    return resourcePath;
  }

  void _validateDatabase(DatabaseId other, String type) {
    final DatabaseId own = _firestore.databaseId;
    if (other != own) {
      throw ArgumentError('Invalid $type. The project ID '
          '("${other.projectId}") or the database ("${other.databaseId}") '
          'does not match the project ID ("${own.projectId}") and database '
          '("${own.databaseId}") of the target database of this Pipeline.');
    }
  }
}
