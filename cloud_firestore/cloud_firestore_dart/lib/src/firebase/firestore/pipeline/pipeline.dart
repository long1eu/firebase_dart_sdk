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

import 'package:cloud_firestore_dart/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/stage.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:meta/meta.dart';

/// How the server chooses indexes for a pipeline.
enum PipelineIndexMode {
  /// Let the server use the indexes it recommends.
  recommended('recommended');

  const PipelineIndexMode(this.serverName);

  @internal
  final String serverName;
}

/// What the server reports about how it runs a pipeline.
enum PipelineExplainMode {
  /// Run the pipeline and report the plan together with execution
  /// statistics.
  analyze('analyze'),

  /// Only report the plan.
  explain('explain');

  const PipelineExplainMode(this.serverName);

  /// The name the server knows this mode by.
  @internal
  final String serverName;
}

/// The format of [PipelineExplainStats].
enum PipelineExplainOutputFormat {
  /// Human readable text.
  text('text'),

  /// A JSON document.
  json('json');

  const PipelineExplainOutputFormat(this.serverName);

  /// The name the server knows this format by.
  @internal
  final String serverName;
}

/// Asks the server to explain how it runs a pipeline; pass it to
/// [Pipeline.execute].
///
/// **Not verified**: the other client SDKs do not have this option yet and
/// the emulator ignores it, so the option names sent here (`explain_options`
/// with `mode` and `output_format`) are taken from the API description and
/// have not been checked against a real backend.
class PipelineExplainOptions {
  /// Explain in [mode], formatting the answer as [outputFormat] (the server
  /// default when null).
  const PipelineExplainOptions(
      {this.mode = PipelineExplainMode.analyze, this.outputFormat});

  /// What to report.
  final PipelineExplainMode mode;

  /// The format of the report, or null for the server default.
  final PipelineExplainOutputFormat? outputFormat;

  /// The wire form of these options.
  @internal
  pb.Value toProto() {
    final PipelineExplainOutputFormat? format = outputFormat;
    return pb.Value()
      ..mapValue = (pb.MapValue()
        ..fields['mode'] = stringValue(mode.serverName)
        ..fields.addAll(<String, pb.Value>{
          if (format != null) 'output_format': stringValue(format.serverName),
        }));
  }
}

/// A query made of an ordered list of stages, executed by the server.
///
/// Start one with `firestore.pipeline()` and a source such as
/// `collection('books')`, then add stages. A pipeline is immutable: every
/// stage method returns a new pipeline.
///
/// ```dart
/// final snapshot = await firestore
///     .pipeline()
///     .collection('books')
///     .where(field('rating').greaterThan(4))
///     .sort([field('rating').descending()])
///     .limit(10)
///     .execute();
/// ```
///
/// Pipelines need a Firestore **Enterprise edition** database. They are always
/// executed by the server: they do not read or update the local cache, do not
/// see pending writes, fail with `unavailable` while offline and cannot be
/// listened to.
///
/// Every stage accepts `rawOptions`, named options sent to the server as they
/// are, for options this SDK has no parameter for yet.
///
/// **Preview**: the Pipelines API is experimental and may change.
class Pipeline {
  @internal
  Pipeline(this.firestore, List<Stage> stages)
      : stages = List<Stage>.unmodifiable(stages);

  /// The database this pipeline runs against.
  final Firestore firestore;

  @internal
  final List<Stage> stages;

  Pipeline _append(Stage stage) =>
      Pipeline(firestore, <Stage>[...stages, stage]);

  /// Keeps only the inputs for which [condition] holds.
  Pipeline where(BooleanExpression condition,
      {Map<String, Object?>? rawOptions}) {
    return _append(Stage(
      'where',
      args: <pb.Value Function(PipelineEncoder)>[condition.toProto],
      rawOptions: rawOptions,
    ));
  }

  /// Outputs only the given [selections]: field names (`String`), [Field]s or
  /// expressions with an alias (`field('a').add(1).as('b')`).
  Pipeline select(List<Object> selections, {Map<String, Object?>? rawOptions}) {
    return _expressionMapStage('select', 'select', selections, rawOptions);
  }

  /// Adds the given aliased expressions as [fields] to every input, keeping
  /// the existing fields.
  Pipeline addFields(List<Selectable> fields,
      {Map<String, Object?>? rawOptions}) {
    return _expressionMapStage('add_fields', 'addFields', fields, rawOptions);
  }

  /// Removes the given [fields] (`String` names or [Field]s) from every
  /// input.
  Pipeline removeFields(List<Object> fields,
      {Map<String, Object?>? rawOptions}) {
    _requireNotEmpty(fields, 'removeFields');
    final List<Field> converted = fields
        .map((Object f) => f is Field ? f : Field.of(f))
        .toList(growable: false);
    return _append(Stage(
      'remove_fields',
      args: <pb.Value Function(PipelineEncoder)>[
        for (final Field field in converted) field.toProto,
      ],
      rawOptions: rawOptions,
    ));
  }

  /// Sorts the inputs by [orderings], the first one being the most
  /// significant.
  Pipeline sort(List<Ordering> orderings, {Map<String, Object?>? rawOptions}) {
    _requireNotEmpty(orderings, 'sort');
    final List<Ordering> copy = List<Ordering>.of(orderings);
    return _append(Stage(
      'sort',
      args: <pb.Value Function(PipelineEncoder)>[
        for (final Ordering ordering in copy) ordering.toProto,
      ],
      rawOptions: rawOptions,
    ));
  }

  /// Keeps at most the first [limit] inputs.
  Pipeline limit(int limit, {Map<String, Object?>? rawOptions}) {
    if (limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'must not be negative');
    }
    return _append(Stage(
      'limit',
      args: <pb.Value Function(PipelineEncoder)>[(_) => integerValue(limit)],
      rawOptions: rawOptions,
    ));
  }

  /// Skips the first [offset] inputs.
  Pipeline offset(int offset, {Map<String, Object?>? rawOptions}) {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must not be negative');
    }
    return _append(Stage(
      'offset',
      args: <pb.Value Function(PipelineEncoder)>[(_) => integerValue(offset)],
      rawOptions: rawOptions,
    ));
  }

  /// Combines the inputs into one result per group, computing
  /// [accumulators] for each.
  ///
  /// [groups] are field names (`String`), [Field]s or aliased expressions.
  /// Without groups there is a single result for all inputs.
  ///
  /// ```dart
  /// pipeline.aggregate(
  ///   [field('rating').average().as('avgRating'), countAll().as('count')],
  ///   groups: ['genre'],
  /// );
  /// ```
  Pipeline aggregate(List<AliasedAggregate> accumulators,
      {List<Object> groups = const <Object>[],
      Map<String, Object?>? rawOptions}) {
    _requireNotEmpty(accumulators, 'aggregate');
    final Map<String, AggregateFunction> accumulatorMap =
        <String, AggregateFunction>{};
    for (final AliasedAggregate aliased in accumulators) {
      if (accumulatorMap.containsKey(aliased.alias)) {
        throw ArgumentError(
            "Duplicate alias or field '${aliased.alias}' in aggregate().");
      }
      accumulatorMap[aliased.alias] = aliased.aggregate;
    }
    final Map<String, Expression> groupMap =
        selectablesToMap(groups, method: 'aggregate');
    return _append(Stage(
      'aggregate',
      args: <pb.Value Function(PipelineEncoder)>[
        (PipelineEncoder encoder) {
          final pb.MapValue map = pb.MapValue();
          accumulatorMap.forEach((String alias, AggregateFunction function) {
            map.fields[alias] = function.toProto(encoder);
          });
          return pb.Value()..mapValue = map;
        },
        (PipelineEncoder encoder) => encodeExpressionMap(encoder, groupMap),
      ],
      rawOptions: rawOptions,
    ));
  }

  /// Outputs one result for every distinct combination of [groups]: field
  /// names (`String`), [Field]s or aliased expressions.
  Pipeline distinct(List<Object> groups, {Map<String, Object?>? rawOptions}) {
    return _expressionMapStage('distinct', 'distinct', groups, rawOptions);
  }

  /// Keeps the inputs whose vector [field] (a `String` name or a [Field]) is
  /// nearest to [vector] (a [VectorValue], a `List<double>` or an
  /// [Expression]), nearest first.
  ///
  /// [limit] bounds the number of results. With [distanceField] the computed
  /// distance is added to every result under that name.
  Pipeline findNearest(
    Object field,
    Object vector,
    DistanceMeasure distanceMeasure, {
    int? limit,
    String? distanceField,
    Map<String, Object?>? rawOptions,
  }) {
    final Field vectorField = field is Field ? field : Field.of(field);
    final Expression vectorExpression;
    if (vector is Expression) {
      vectorExpression = vector;
    } else if (vector is VectorValue) {
      vectorExpression = Constant(vector);
    } else if (vector is List<double>) {
      vectorExpression = Constant(VectorValue(vector));
    } else {
      throw ArgumentError(
          'findNearest() expects a VectorValue, a List<double> or an '
          'Expression as the vector, but got: $vector');
    }
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final String measure;
    switch (distanceMeasure) {
      case DistanceMeasure.euclidean:
        measure = 'euclidean';
        break;
      case DistanceMeasure.cosine:
        measure = 'cosine';
        break;
      case DistanceMeasure.dotProduct:
        measure = 'dot_product';
        break;
    }
    return _append(Stage(
      'find_nearest',
      args: <pb.Value Function(PipelineEncoder)>[
        vectorField.toProto,
        vectorExpression.toProto,
        (_) => stringValue(measure),
      ],
      options: <String, pb.Value Function(PipelineEncoder)>{
        if (limit != null) 'limit': (_) => integerValue(limit),
        if (distanceField != null)
          'distance_field': Field.of(distanceField).toProto,
      },
      rawOptions: rawOptions,
    ));
  }

  /// Keeps a random sample of the inputs: either a number of [documents], or
  /// a [percentage] of them between 0 and 1. Exactly one must be given.
  Pipeline sample(
      {int? documents, double? percentage, Map<String, Object?>? rawOptions}) {
    if ((documents == null) == (percentage == null)) {
      throw ArgumentError(
          'sample() needs exactly one of documents and percentage.');
    }
    return _append(Stage(
      'sample',
      args: <pb.Value Function(PipelineEncoder)>[
        (_) => documents != null
            ? integerValue(documents)
            : doubleValue(percentage!),
        (_) => stringValue(documents != null ? 'documents' : 'percent'),
      ],
      rawOptions: rawOptions,
    ));
  }

  /// Appends the results of [other] to the results of this pipeline. The
  /// order of the combined results is not defined.
  Pipeline union(Pipeline other, {Map<String, Object?>? rawOptions}) {
    return _append(Stage(
      'union',
      args: <pb.Value Function(PipelineEncoder)>[
        (PipelineEncoder encoder) =>
            pb.Value()..pipelineValue = other.toProto(encoder),
      ],
      rawOptions: rawOptions,
    ));
  }

  /// Outputs one result per element of an array: [selectable] is the array
  /// expression with the alias under which each element is stored
  /// (`field('tags').as('tag')`).
  ///
  /// With [indexField] the position of the element in the array is stored
  /// under that name.
  Pipeline unnest(Selectable selectable,
      {String? indexField, Map<String, Object?>? rawOptions}) {
    final Field alias = Field.of(selectable.alias);
    return _append(Stage(
      'unnest',
      args: <pb.Value Function(PipelineEncoder)>[
        selectable.expression.toProto,
        alias.toProto,
      ],
      options: <String, pb.Value Function(PipelineEncoder)>{
        if (indexField != null) 'index_field': Field.of(indexField).toProto,
      },
      rawOptions: rawOptions,
    ));
  }

  /// Replaces every input with the map that [fieldOrExpression] evaluates to:
  /// a field name (`String`) or an [Expression].
  Pipeline replaceWith(Object fieldOrExpression,
      {Map<String, Object?>? rawOptions}) {
    final Expression expression = fieldOrExpression is String
        ? Field.of(fieldOrExpression)
        : fieldOrExpression is Expression
            ? fieldOrExpression
            : throw ArgumentError(
                'replaceWith() takes a field name or an Expression, but got: '
                '$fieldOrExpression');
    return _append(Stage(
      'replace_with',
      args: <pb.Value Function(PipelineEncoder)>[
        expression.toProto,
        (_) => stringValue('full_replace'),
      ],
      rawOptions: rawOptions,
    ));
  }

  /// Defines variables for the following stages and for subqueries used in
  /// them: every aliased expression becomes the variable with that name, read
  /// with `variable(name)`.
  ///
  /// ```dart
  /// firestore.pipeline().collection('authors')
  ///     .define([field('name').as('authorName')])
  ///     .addFields([
  ///       firestore.pipeline().collection('books')
  ///           .where(field('author').equal(variable('authorName')))
  ///           .aggregate([countAll().as('count')])
  ///           .toScalarExpression().as('bookCount'),
  ///     ]);
  /// ```
  Pipeline define(List<AliasedExpression> variables,
      {Map<String, Object?>? rawOptions}) {
    return _expressionMapStage('let', 'define', variables, rawOptions);
  }

  /// This pipeline as an expression that evaluates to the array of its
  /// results, for use in a stage of another pipeline (a subquery).
  ///
  /// A pipeline that outputs a single field yields an array of the values of
  /// that field; otherwise every element is a map of the fields of a result.
  Expression toArrayExpression() => FunctionExpression(
      'array', <Object?>[RawValueExpression(_toPipelineValue, toString())]);

  /// This pipeline as an expression that evaluates to its single result, for
  /// use in a stage of another pipeline (a subquery). The pipeline must
  /// produce at most one result; with a single output field the expression
  /// is the value of that field.
  Expression toScalarExpression() => FunctionExpression(
      'scalar', <Object?>[RawValueExpression(_toPipelineValue, toString())]);

  pb.Value _toPipelineValue(PipelineEncoder encoder) =>
      pb.Value()..pipelineValue = toProto(encoder);

  /// Deletes every input document. The result of the pipeline is one row
  /// with the number of `documents_modified`.
  ///
  /// The write stages ([delete], [update], [insert], [upsert]) change the
  /// database directly on the server. They are not queued while offline, do
  /// not go through the local cache and do not raise local events; listeners
  /// see the change when the server reports it (the emulator does not report
  /// it at all, see the README). Use `execute(atomic: true)` to apply all
  /// writes of a pipeline in one transaction; the server requires it whenever
  /// it cannot apply the stages to one document at a time, for example for
  /// [insert] and [upsert] of documents read from a collection, or after an
  /// aggregation, `unnest`, `union` or a subquery.
  Pipeline delete({Map<String, Object?>? rawOptions}) {
    return _append(Stage('delete', rawOptions: rawOptions));
  }

  /// Writes every input document back to where it was read from.
  ///
  /// With [transformedFields] only those fields are written, with the values
  /// of the given aliased expressions. Without them the documents are
  /// written as the preceding stages left them (for example after
  /// `addFields`). See [delete] for how write stages behave.
  Pipeline update(
      {List<Selectable> transformedFields = const <Selectable>[],
      Map<String, Object?>? rawOptions}) {
    final Map<String, Expression> fields =
        selectablesToMap(transformedFields, method: 'update');
    return _append(Stage(
      'update',
      args: <pb.Value Function(PipelineEncoder)>[
        (PipelineEncoder encoder) => encodeExpressionMap(encoder, fields),
      ],
      rawOptions: rawOptions,
    ));
  }

  /// Creates a document from every input; fails with `already-exists` if one
  /// of them exists.
  ///
  /// [collection] (a path or a `CollectionReference`) is where the documents
  /// are created; without it they are created where the inputs were read
  /// from. [documentId] (a field name or an [Expression]) gives the id of
  /// each new document; without it the server assigns ids. See [delete] for
  /// how write stages behave.
  Pipeline insert(
      {Object? collection,
      Object? documentId,
      Map<String, Object?>? rawOptions}) {
    return _append(Stage(
      'insert',
      options: _writeTarget('insert', collection, documentId),
      rawOptions: rawOptions,
    ));
  }

  /// Creates or replaces a document from every input.
  ///
  /// [additionalFields] are aliased expressions that are written on top of
  /// the input. [collection] and [documentId] are as for [insert]. See
  /// [delete] for how write stages behave.
  Pipeline upsert(
      {List<Selectable> additionalFields = const <Selectable>[],
      Object? collection,
      Object? documentId,
      Map<String, Object?>? rawOptions}) {
    final Map<String, Expression> fields =
        selectablesToMap(additionalFields, method: 'upsert');
    return _append(Stage(
      'upsert',
      args: <pb.Value Function(PipelineEncoder)>[
        (PipelineEncoder encoder) => encodeExpressionMap(encoder, fields),
      ],
      options: _writeTarget('upsert', collection, documentId),
      rawOptions: rawOptions,
    ));
  }

  Map<String, pb.Value Function(PipelineEncoder)> _writeTarget(
      String method, Object? collection, Object? documentId) {
    final String? path = collection == null
        ? null
        : PipelineSource.collectionPath(firestore, collection, method);
    final Expression? id =
        documentId == null ? null : fieldOrExpression(documentId);
    return <String, pb.Value Function(PipelineEncoder)>{
      if (path != null) 'collection': (_) => relativeReferenceValue(path),
      if (id != null) 'document_id': id.toProto,
    };
  }

  /// Adds a stage this SDK has no method for: [name] is the server name of
  /// the stage (snake case), [args] its positional arguments (values or
  /// [Expression]s) and [options] its named options.
  Pipeline rawStage(String name, List<Object?> args,
      {Map<String, Object?>? options}) {
    final List<Object?> copy = List<Object?>.of(args);
    return _append(Stage(
      name,
      args: <pb.Value Function(PipelineEncoder)>[
        for (final Object? arg in copy)
          (PipelineEncoder encoder) => arg is Expression
              ? arg.toProto(encoder)
              : arg is Map
                  ? encodeExpressionMap(encoder, <String, Expression>{
                      for (final MapEntry<Object?, Object?> entry
                          in arg.entries)
                        entry.key! as String: toExpression(entry.value),
                    })
                  : toExpression(arg).toProto(encoder),
      ],
      rawOptions: options,
    ));
  }

  /// Executes this pipeline on the server.
  ///
  /// [rawOptions] are named options sent to the server as they are.
  ///
  /// With [atomic] the pipeline runs in a read-write transaction that is
  /// committed when it completes, so the writes of a write stage ([delete],
  /// [update], [insert], [upsert]) are applied together or not at all.
  ///
  /// With [explainOptions] the server is asked to describe how it runs the
  /// pipeline; the answer is in [PipelineSnapshot.explainStats].
  Future<PipelineSnapshot> execute({
    bool atomic = false,
    PipelineIndexMode? indexMode,
    PipelineExplainOptions? explainOptions,
    Map<String, Object?>? rawOptions,
  }) async {
    if (stages.isNotEmpty && stages.first.name == 'subcollection') {
      throw StateError(
          'This pipeline starts at a subcollection of the document of an '
          'enclosing pipeline and cannot be executed directly. It can only '
          'be used as part of another pipeline.');
    }
    final PipelineEncoder encoder = PipelineEncoder(firestore.databaseId);
    final proto.ExecutePipelineRequest request = toExecuteRequest(encoder,
        atomic: atomic,
        indexMode: indexMode,
        explainOptions: explainOptions,
        rawOptions: rawOptions);
    final List<proto.ExecutePipelineResponse> responses =
        await firestore.client.executePipeline(request);
    return decodePipelineResponses(
        this, firestore, encoder.serializer, responses);
  }

  /// Builds the request that [execute] sends.
  @internal
  proto.ExecutePipelineRequest toExecuteRequest(
    PipelineEncoder encoder, {
    bool atomic = false,
    PipelineIndexMode? indexMode,
    PipelineExplainOptions? explainOptions,
    Map<String, Object?>? rawOptions,
  }) {
    final proto.StructuredPipeline structured = proto.StructuredPipeline()
      ..pipeline = toProto(encoder);
    if (indexMode != null) {
      structured.options['index_mode'] = stringValue(indexMode.serverName);
    }
    if (explainOptions != null) {
      structured.options['explain_options'] = explainOptions.toProto();
    }
    structured.options.addAll(encodeOptions(encoder, rawOptions));
    final proto.ExecutePipelineRequest request = proto.ExecutePipelineRequest()
      ..database = encoder.serializer.databaseName
      ..structuredPipeline = structured;
    if (atomic) {
      request
        ..newTransaction = (proto.TransactionOptions()
          ..readWrite = (proto.TransactionOptions_ReadWrite()
            ..concurrencyMode =
                proto.TransactionOptions_ConcurrencyMode.OPTIMISTIC))
        ..autoCommitTransaction = true;
    }
    return request;
  }

  /// The wire representation of the stages.
  @internal
  proto.Pipeline toProto(PipelineEncoder encoder) {
    return proto.Pipeline()
      ..stages.addAll(stages.map((Stage stage) => stage.toProto(encoder)));
  }

  Pipeline _expressionMapStage(String name, String method,
      List<Object> selectables, Map<String, Object?>? rawOptions) {
    _requireNotEmpty(selectables, method);
    final Map<String, Expression> map =
        selectablesToMap(selectables, method: method);
    return _append(Stage(
      name,
      args: <pb.Value Function(PipelineEncoder)>[
        (PipelineEncoder encoder) => encodeExpressionMap(encoder, map),
      ],
      rawOptions: rawOptions,
    ));
  }

  static void _requireNotEmpty(List<Object?> values, String method) {
    if (values.isEmpty) {
      throw ArgumentError('$method() needs at least one argument.');
    }
  }

  @override
  String toString() =>
      'Pipeline(${stages.map((Stage s) => s.name).join(' | ')})';
}
