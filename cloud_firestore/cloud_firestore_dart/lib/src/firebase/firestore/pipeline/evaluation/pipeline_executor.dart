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

/// Runs pipelines over a set of documents, as the backend would.
///
/// The semantics are those of the Enterprise edition emulator (see
/// `test/integration_enterprise/pipeline_executor_property_test.dart`):
///
/// - A stage expression that evaluates to an error fails the whole pipeline
///   (the backend answers INVALID_ARGUMENT), as do the stage arguments the
///   backend rejects before running (a select of `a` and `a.b`, an
///   aggregate whose names overlap, ...). Both are a [PipelineFailure].
/// - `sort` orders null and missing values first, as equal, then values in
///   the order of all Firestore values (numbers by value: 1 equals 1.0).
/// - `distinct` and the groups of `aggregate` put equal values together
///   (null with missing, 1 with 1.0); which of the equal values a group
///   shows is not specified.
/// - `select`, `aggregate`, `distinct` and `replace_with` drop the document
///   (`__name__`, `__create_time__`, `__update_time__`); the other stages keep
///   it.
///
/// What is not run locally throws an [UnsupportedExpression]: the `sample`,
/// `let` (`define`), `subcollection`, `literals`, `search`,
/// `add_window_fields` and write stages,
/// stages and options this file does not know, and the expressions the
/// [ExpressionEvaluator] does not evaluate.
library;

import 'dart:math' as math;

import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/aggregate_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;

/// The backend would fail the pipeline: an expression of a stage evaluated
/// to an error, or the stages are invalid.
class PipelineFailure implements Exception {
  PipelineFailure(this.message);

  final String message;

  @override
  String toString() => 'PipelineFailure: $message';
}

/// Runs pipelines locally.
class PipelineExecutor {
  PipelineExecutor(
    this.databaseId, {
    Timestamp Function()? now,
    math.Random? random,
  }) : expressions = ExpressionEvaluator(databaseId, now: now, random: random);

  final DatabaseId databaseId;

  /// Evaluates the expressions of the stages.
  final ExpressionEvaluator expressions;

  late final AggregateEvaluator _aggregates = AggregateEvaluator(expressions);

  /// The names of the stages that run locally.
  static const Set<String> supportedStages = <String>{
    'collection',
    'collection_group',
    'database',
    'documents',
    'where',
    'select',
    'add_fields',
    'remove_fields',
    'sort',
    'limit',
    'offset',
    'distinct',
    'aggregate',
    'unnest',
    'union',
    'replace_with',
    'find_nearest',
  };

  /// Runs [pipeline] over [documents]: every document its sources may read
  /// (inputs with a [EvaluationInput.key]). The first stage has to be a
  /// source.
  ///
  /// The order of the results is the backend's only where the pipeline
  /// defines it: after a `sort` (equal sort keys keep the order they had),
  /// and after `find_nearest`. Elsewhere it is the order of [documents].
  ///
  /// Throws a [PipelineFailure] where the backend would fail, and an
  /// [UnsupportedExpression] for a pipeline that is not run locally.
  List<EvaluationInput> execute(
    pb.Pipeline pipeline,
    Iterable<EvaluationInput> documents,
  ) {
    final List<EvaluationInput> all = documents.toList(growable: false);
    if (pipeline.stages.isEmpty) {
      throw PipelineFailure('A pipeline needs a source stage');
    }
    List<EvaluationInput> rows = _source(pipeline.stages.first, all);
    for (final pb.Pipeline_Stage stage in pipeline.stages.skip(1)) {
      rows = _stage(stage, rows, all);
    }
    return rows;
  }

  // ---- sources ----

  List<EvaluationInput> _source(
    pb.Pipeline_Stage stage,
    List<EvaluationInput> documents,
  ) {
    switch (stage.name) {
      case 'collection':
        _options(stage, const <String>{'force_index'});
        final ResourcePath path = _path(_reference(stage, 0));
        return <EvaluationInput>[
          for (final EvaluationInput document in documents)
            if (_key(document).path.popLast() == path) document,
        ];
      case 'collection_group':
        _options(stage, const <String>{'force_index'});
        _arguments(stage, 2);
        if (_path(_reference(stage, 0)).isNotEmpty) {
          throw UnsupportedExpression(
            'A collection group under a document is not run locally',
          );
        }
        final String id = _string(stage, 1);
        return <EvaluationInput>[
          for (final EvaluationInput document in documents)
            if (_key(document).hasCollectionId(id)) document,
        ];
      case 'database':
        _options(stage, const <String>{});
        _arguments(stage, 0);
        return documents;
      case 'documents':
        _options(stage, const <String>{});
        final List<EvaluationInput> result = <EvaluationInput>[];
        for (int i = 0; i < stage.args.length; i++) {
          final ResourcePath path = _path(_reference(stage, i));
          for (final EvaluationInput document in documents) {
            if (_key(document).path == path) {
              result.add(document);
            }
          }
        }
        return result;
    }
    if (supportedStages.contains(stage.name)) {
      throw PipelineFailure('A pipeline starts with a source stage');
    }
    throw UnsupportedExpression('The stage ${stage.name} is not run locally');
  }

  // ---- the other stages ----

  List<EvaluationInput> _stage(
    pb.Pipeline_Stage stage,
    List<EvaluationInput> rows,
    List<EvaluationInput> documents,
  ) {
    switch (stage.name) {
      case 'where':
        _options(stage, const <String>{});
        _arguments(stage, 1);
        return <EvaluationInput>[
          for (final EvaluationInput row in rows)
            if (_value(stage.args[0], row) case final BoolValue value
                when value.value)
              row,
        ];
      case 'select':
        _options(stage, const <String>{});
        _arguments(stage, 1);
        final List<(FieldPath, pb.Value)> fields = _fields(stage, 0);
        return <EvaluationInput>[
          for (final EvaluationInput row in rows)
            EvaluationInput(_set(ObjectValue.empty, fields, row)),
        ];
      case 'add_fields':
        _options(stage, const <String>{});
        _arguments(stage, 1);
        final List<(FieldPath, pb.Value)> fields = _fields(stage, 0);
        return <EvaluationInput>[
          for (final EvaluationInput row in rows)
            _withFields(row, _set(row.fields, fields, row)),
        ];
      case 'remove_fields':
        _options(stage, const <String>{});
        final List<FieldPath> paths = <FieldPath>[
          for (final pb.Value arg in stage.args) _fieldPath(arg),
        ];
        return <EvaluationInput>[
          for (final EvaluationInput row in rows)
            _withFields(
              row,
              paths.fold(
                row.fields,
                (ObjectValue fields, FieldPath path) => fields.delete(path),
              ),
            ),
        ];
      case 'sort':
        _options(stage, const <String>{});
        return _sort(stage, rows);
      case 'limit':
        _options(stage, const <String>{});
        _arguments(stage, 1);
        return rows.take(_count(stage)).toList();
      case 'offset':
        _options(stage, const <String>{});
        _arguments(stage, 1);
        return rows.skip(_count(stage)).toList();
      case 'distinct':
        _options(stage, const <String>{});
        _arguments(stage, 1);
        final List<(String, pb.Value)> groups = _topLevelFields(stage, 0);
        return <EvaluationInput>[
          for (final _Group group in _groups(groups, rows))
            EvaluationInput(_groupFields(groups, group)),
        ];
      case 'aggregate':
        _options(stage, const <String>{});
        _arguments(stage, 2);
        return _aggregate(stage, rows);
      case 'unnest':
        _options(stage, const <String>{'index_field'});
        return _unnest(stage, rows);
      case 'union':
        _options(stage, const <String>{});
        _arguments(stage, 1);
        final pb.Value other = stage.args[0];
        if (other.whichValueType() != pb.Value_ValueType.pipelineValue) {
          throw PipelineFailure('union() takes a pipeline');
        }
        return <EvaluationInput>[
          ...rows,
          ...execute(other.pipelineValue, documents),
        ];
      case 'replace_with':
        _options(stage, const <String>{});
        _arguments(stage, 2);
        if (_string(stage, 1) != 'full_replace') {
          throw UnsupportedExpression(
            'replace_with in the mode ${_string(stage, 1)} is not run locally',
          );
        }
        return <EvaluationInput>[
          for (final EvaluationInput row in rows)
            EvaluationInput(switch (_value(stage.args[0], row)) {
              final ObjectValue map => map,
              _ => ObjectValue.empty,
            }),
        ];
      case 'find_nearest':
        _options(stage, const <String>{'limit', 'distance_field'});
        return _findNearest(stage, rows);
      case 'add_window_fields':
        // Android's AddWindowFieldsStage has no local evaluation and JS has
        // no local pipeline runner for it; the emulator rejects the stage, so
        // there is no reference for its frames, ties and defaults either.
        throw UnsupportedExpression(
          'The stage add_window_fields (window functions) is not run '
          'locally: no SDK evaluates it offline and the emulator does not '
          'support it, so there is no reference for its semantics',
        );
      case 'search':
        throw UnsupportedExpression(
          'The stage search is not run locally: full-text and geo search '
          'need the search index of the backend',
        );
    }
    if (const <String>{
      'collection',
      'collection_group',
      'database',
      'documents',
    }.contains(stage.name)) {
      throw PipelineFailure('Only the first stage can be a source');
    }
    throw UnsupportedExpression('The stage ${stage.name} is not run locally');
  }

  List<EvaluationInput> _sort(
    pb.Pipeline_Stage stage,
    List<EvaluationInput> rows,
  ) {
    if (stage.args.isEmpty) {
      throw PipelineFailure('sort() needs an ordering');
    }
    final List<(pb.Value, bool)> orderings = <(pb.Value, bool)>[];
    for (final pb.Value arg in stage.args) {
      final pb.MapValue map = arg.mapValue;
      final pb.Value? expression = map.fields['expression'];
      final String? direction = map.fields['direction']?.stringValue;
      if (expression == null ||
          (direction != 'ascending' && direction != 'descending')) {
        throw PipelineFailure('Not an ordering: $arg');
      }
      orderings.add((expression, direction == 'descending'));
    }
    // The keys of every row first: an error in any of them fails the
    // pipeline, whatever the order.
    final List<(EvaluationInput, List<FieldValue?>)> keyed =
        <(EvaluationInput, List<FieldValue?>)>[
          for (final EvaluationInput row in rows)
            (
              row,
              <FieldValue?>[
                for (final (pb.Value expression, bool _) in orderings)
                  _value(expression, row),
              ],
            ),
        ];
    return _stableSort(keyed, (List<FieldValue?> a, List<FieldValue?> b) {
      for (int i = 0; i < orderings.length; i++) {
        final int order = sortOrder(a[i], b[i]);
        if (order != 0) {
          return orderings[i].$2 ? -order : order;
        }
      }
      return 0;
    }).map(((EvaluationInput, List<FieldValue?>) e) => e.$1).toList();
  }

  List<EvaluationInput> _aggregate(
    pb.Pipeline_Stage stage,
    List<EvaluationInput> rows,
  ) {
    final List<(String, pb.Value)> accumulators = _topLevelFields(stage, 0);
    final List<(String, pb.Value)> groups = _topLevelFields(stage, 1);
    final Set<String> names = <String>{};
    for (final (String name, pb.Value _) in <(String, pb.Value)>[
      ...accumulators,
      ...groups,
    ]) {
      if (!names.add(name)) {
        throw PipelineFailure('aggregate() has the name $name twice');
      }
    }
    if (accumulators.isEmpty) {
      throw PipelineFailure('aggregate() needs an accumulator');
    }
    for (final (String _, pb.Value function) in accumulators) {
      if (function.whichValueType() != pb.Value_ValueType.functionValue ||
          !AggregateEvaluator.supports(function.functionValue.name)) {
        throw UnsupportedExpression(
          'The aggregate ${function.functionValue.name}() is not evaluated '
          'locally',
        );
      }
    }
    final List<_Group> grouped = groups.isEmpty
        ? <_Group>[_Group(const <FieldValue?>[], rows)]
        : _groups(groups, rows);
    return <EvaluationInput>[
      for (final _Group group in grouped)
        EvaluationInput(
          _accumulate(accumulators, group, _groupFields(groups, group)),
        ),
    ];
  }

  ObjectValue _accumulate(
    List<(String, pb.Value)> accumulators,
    _Group group,
    ObjectValue fields,
  ) {
    ObjectValue result = fields;
    for (final (String name, pb.Value function) in accumulators) {
      final EvaluateResult value = _aggregates.aggregate(function, group.rows);
      if (value.isError) {
        throw PipelineFailure('The aggregate $name failed');
      }
      result = result.set(
        FieldPath.fromSingleSegment(name),
        value.value ?? NullValue.nullValue(),
      );
    }
    return result;
  }

  List<EvaluationInput> _unnest(
    pb.Pipeline_Stage stage,
    List<EvaluationInput> rows,
  ) {
    _arguments(stage, 2);
    final String alias = _topLevelField(stage.args[1]);
    final pb.Value? indexArg = stage.options['index_field'];
    final String? index = indexArg == null ? null : _topLevelField(indexArg);
    if (index == alias) {
      throw PipelineFailure('The index field of unnest() is its alias');
    }
    final FieldPath aliasPath = FieldPath.fromSingleSegment(alias);
    final FieldPath? indexPath = index == null
        ? null
        : FieldPath.fromSingleSegment(index);
    ObjectValue withIndex(ObjectValue fields, FieldValue value) =>
        indexPath == null ? fields : fields.set(indexPath, value);

    final List<EvaluationInput> result = <EvaluationInput>[];
    for (final EvaluationInput row in rows) {
      final FieldValue? value = _value(stage.args[0], row);
      if (value is ArrayValue) {
        // An empty array has no rows.
        final List<FieldValue> elements = value.internalValue;
        for (int i = 0; i < elements.length; i++) {
          result.add(
            _withFields(
              row,
              withIndex(
                row.fields.set(aliasPath, elements[i]),
                IntegerValue.valueOf(i),
              ),
            ),
          );
        }
      } else {
        // Not an array: the input once, with the value itself (none for a
        // missing one) and no index.
        final ObjectValue fields = value == null
            ? row.fields.delete(aliasPath)
            : row.fields.set(aliasPath, value);
        result.add(_withFields(row, withIndex(fields, NullValue.nullValue())));
      }
    }
    return result;
  }

  List<EvaluationInput> _findNearest(
    pb.Pipeline_Stage stage,
    List<EvaluationInput> rows,
  ) {
    _arguments(stage, 3);
    final pb.Value field = stage.args[0];
    if (field.whichValueType() != pb.Value_ValueType.fieldReferenceValue) {
      throw PipelineFailure('find_nearest() takes a field');
    }
    final String measure = _string(stage, 2);
    final String function = switch (measure) {
      'euclidean' => 'euclidean_distance',
      'cosine' => 'cosine_distance',
      'dot_product' => 'dot_product',
      _ => throw UnsupportedExpression(
        'The distance measure $measure is not evaluated locally',
      ),
    };
    final FieldValue? query = _value(
      stage.args[1],
      EvaluationInput(ObjectValue.empty),
    );
    if (query is! VectorFieldValue) {
      throw UnsupportedExpression(
        'find_nearest() with a vector that is not a constant is not run '
        'locally',
      );
    }
    final pb.Value? limitArg = stage.options['limit'];
    final int? limit = limitArg == null ? null : _integer(limitArg);
    final pb.Value? distanceArg = stage.options['distance_field'];
    final FieldPath? distanceField = distanceArg == null
        ? null
        : FieldPath.fromSingleSegment(_topLevelField(distanceArg));

    final pb.Value distance = pb.Value()
      ..functionValue = (pb.Function_()
        ..name = function
        ..args.addAll(<pb.Value>[field, stage.args[1]]));
    final List<(EvaluationInput, List<FieldValue?>)> scored =
        <(EvaluationInput, List<FieldValue?>)>[];
    for (final EvaluationInput row in rows) {
      // Only vectors of the dimension of the query.
      final FieldValue? value = row.fields.get(
        FieldPath.fromServerFormat(field.fieldReferenceValue),
      );
      if (value is! VectorFieldValue ||
          value.value.length != query.value.length) {
        continue;
      }
      final FieldValue? score;
      if (measure == 'cosine' &&
          (_isZero(value.value.toArray()) || _isZero(query.value.toArray()))) {
        // The function cosine_distance() fails for a zero vector; here the
        // distance is NaN, and the input stays.
        score = DoubleValue.valueOf(double.nan);
      } else {
        score = expressions.evaluate(distance, row).value;
      }
      if (score is! DoubleValue) {
        continue;
      }
      scored.add((
        distanceField == null
            ? row
            : _withFields(row, row.fields.set(distanceField, score)),
        <FieldValue?>[score],
      ));
    }
    // Nearest first: the smallest distance, or the largest dot product.
    final bool descending = measure == 'dot_product';
    final List<EvaluationInput> sorted = _stableSort(scored, (
      List<FieldValue?> a,
      List<FieldValue?> b,
    ) {
      final int order = sortOrder(a[0], b[0]);
      return descending ? -order : order;
    }).map(((EvaluationInput, List<FieldValue?>) e) => e.$1).toList();
    return limit == null ? sorted : sorted.take(limit).toList();
  }

  // ---- groups ----

  List<_Group> _groups(
    List<(String, pb.Value)> groups,
    List<EvaluationInput> rows,
  ) {
    final List<(EvaluationInput, List<FieldValue?>)> keyed =
        <(EvaluationInput, List<FieldValue?>)>[
          for (final EvaluationInput row in rows)
            (
              row,
              <FieldValue?>[
                for (final (String _, pb.Value expression) in groups)
                  _value(expression, row),
              ],
            ),
        ];
    int compareKeys(List<FieldValue?> a, List<FieldValue?> b) {
      for (int i = 0; i < a.length; i++) {
        final int order = sortOrder(a[i], b[i]);
        if (order != 0) {
          return order;
        }
      }
      return 0;
    }

    // Equal keys next to each other, each group in the order of its inputs;
    // the groups in the order of their first input.
    final List<int> order = List<int>.generate(keyed.length, (int i) => i)
      ..sort((int a, int b) {
        final int byKey = compareKeys(keyed[a].$2, keyed[b].$2);
        return byKey != 0 ? byKey : a.compareTo(b);
      });
    final List<(int, _Group)> result = <(int, _Group)>[];
    for (final int i in order) {
      final (EvaluationInput row, List<FieldValue?> key) = keyed[i];
      if (result.isEmpty || compareKeys(result.last.$2.key, key) != 0) {
        result.add((i, _Group(key, <EvaluationInput>[])));
      }
      result.last.$2.rows.add(row);
    }
    result.sort(((int, _Group) a, (int, _Group) b) => a.$1.compareTo(b.$1));
    return <_Group>[for (final (int _, _Group group) in result) group];
  }

  ObjectValue _groupFields(List<(String, pb.Value)> groups, _Group group) {
    ObjectValue fields = ObjectValue.empty;
    for (int i = 0; i < groups.length; i++) {
      fields = fields.set(
        FieldPath.fromSingleSegment(groups[i].$1),
        group.key[i] ?? NullValue.nullValue(),
      );
    }
    return fields;
  }

  // ---- expressions ----

  /// The value of [expression] for [row], or null when it is missing. An
  /// error fails the pipeline.
  FieldValue? _value(pb.Value expression, EvaluationInput row) {
    final EvaluateResult result = expressions.evaluate(expression, row);
    if (result.isError) {
      throw PipelineFailure('An expression of a stage failed: $expression');
    }
    return result.value;
  }

  /// [fields] (output path and expression) of [row] set in [target]: a
  /// missing value removes the field. The parents of a nested path become
  /// maps (an empty one replaces a value that is not a map) also when the
  /// value is missing.
  ObjectValue _set(
    ObjectValue target,
    List<(FieldPath, pb.Value)> fields,
    EvaluationInput row,
  ) {
    ObjectValue result = target;
    for (final (FieldPath path, pb.Value expression) in fields) {
      final FieldValue? value = _value(expression, row);
      if (value != null) {
        result = result.set(path, value);
      } else if (path.length == 1) {
        result = result.delete(path);
      } else {
        // Setting a placeholder makes the parents maps; then it goes.
        result = result.set(path, NullValue.nullValue()).delete(path);
      }
    }
    return result;
  }

  // ---- arguments ----

  /// The fields of the map argument at [index]: output path and expression.
  /// A path and a path inside it are rejected.
  List<(FieldPath, pb.Value)> _fields(pb.Pipeline_Stage stage, int index) {
    final pb.Value arg = stage.args[index];
    if (arg.whichValueType() != pb.Value_ValueType.mapValue) {
      throw PipelineFailure('${stage.name}() takes a map of expressions');
    }
    final List<(FieldPath, pb.Value)> result = <(FieldPath, pb.Value)>[];
    for (final MapEntry<String, pb.Value> entry
        in arg.mapValue.fields.entries) {
      final FieldPath path = FieldPath.fromServerFormat(entry.key);
      for (final (FieldPath other, pb.Value _) in result) {
        if (other.isPrefixOf(path) || path.isPrefixOf(other)) {
          throw PipelineFailure(
            '${stage.name}() sets $other and $path at the same time',
          );
        }
      }
      result.add((path, entry.value));
    }
    return result;
  }

  /// Like [_fields], for the stages that only take top-level names.
  List<(String, pb.Value)> _topLevelFields(pb.Pipeline_Stage stage, int index) {
    return <(String, pb.Value)>[
      for (final (FieldPath path, pb.Value expression) in _fields(stage, index))
        if (path.length == 1)
          (path.first, expression)
        else
          throw PipelineFailure(
            '${stage.name}() does not take the nested field $path',
          ),
    ];
  }

  String _topLevelField(pb.Value value) {
    final FieldPath path = _fieldPath(value);
    if (path.length != 1) {
      throw PipelineFailure('The nested field $path is not allowed here');
    }
    return path.first;
  }

  FieldPath _fieldPath(pb.Value value) {
    if (value.whichValueType() != pb.Value_ValueType.fieldReferenceValue) {
      throw PipelineFailure('Not a field: $value');
    }
    return FieldPath.fromServerFormat(value.fieldReferenceValue);
  }

  void _arguments(pb.Pipeline_Stage stage, int count) {
    if (stage.args.length != count) {
      throw PipelineFailure(
        '${stage.name}() takes $count arguments, not ${stage.args.length}',
      );
    }
  }

  /// Options other than [known] may change what a stage does.
  void _options(pb.Pipeline_Stage stage, Set<String> known) {
    for (final String option in stage.options.keys) {
      if (!known.contains(option)) {
        throw UnsupportedExpression(
          'The option $option of ${stage.name}() is not run locally',
        );
      }
    }
  }

  String _reference(pb.Pipeline_Stage stage, int index) {
    if (index >= stage.args.length ||
        stage.args[index].whichValueType() !=
            pb.Value_ValueType.referenceValue) {
      throw PipelineFailure('${stage.name}() takes a reference');
    }
    return stage.args[index].referenceValue;
  }

  String _string(pb.Pipeline_Stage stage, int index) {
    if (index >= stage.args.length ||
        stage.args[index].whichValueType() != pb.Value_ValueType.stringValue) {
      throw PipelineFailure('${stage.name}() takes a string');
    }
    return stage.args[index].stringValue;
  }

  int _count(pb.Pipeline_Stage stage) {
    final int count = _integer(stage.args[0]);
    if (count < 0) {
      throw PipelineFailure('${stage.name}() takes a count of at least 0');
    }
    return count;
  }

  int _integer(pb.Value value) {
    if (value.whichValueType() != pb.Value_ValueType.integerValue) {
      throw PipelineFailure('Not an integer: $value');
    }
    return exactInteger(value.integerValue.toInt());
  }

  /// A path relative to the database root (`/users/alice`).
  ResourcePath _path(String reference) {
    final String path = reference.startsWith('/')
        ? reference.substring(1)
        : reference;
    return path.isEmpty
        ? ResourcePath.empty
        : ResourcePath.fromSegments(path.split('/'));
  }

  DocumentKey _key(EvaluationInput document) {
    final DocumentKey? key = document.key;
    if (key == null) {
      throw ArgumentError('A document needs a key: $document');
    }
    return key;
  }
}

/// The order of `sort`: null and missing values first, as equal, then the
/// order of all Firestore values.
int sortOrder(FieldValue? a, FieldValue? b) {
  final bool aNull = a == null || a is NullValue;
  final bool bNull = b == null || b is NullValue;
  if (aNull || bNull) {
    return aNull == bNull ? 0 : (aNull ? -1 : 1);
  }
  return a.compareTo(b);
}

bool _isZero(List<double> vector) => vector.every((double x) => x == 0);

/// The inputs of one group and the values they share.
class _Group {
  _Group(this.key, this.rows);

  final List<FieldValue?> key;
  final List<EvaluationInput> rows;
}

/// [row] with other [fields], still the same document.
EvaluationInput _withFields(EvaluationInput row, ObjectValue fields) =>
    EvaluationInput(
      fields,
      key: row.key,
      createTime: row.createTime,
      updateTime: row.updateTime,
    );

/// [entries] sorted by their keys with [compare]; equal keys keep their
/// order.
List<(EvaluationInput, List<FieldValue?>)> _stableSort(
  List<(EvaluationInput, List<FieldValue?>)> entries,
  int Function(List<FieldValue?> a, List<FieldValue?> b) compare,
) {
  final List<int> order = List<int>.generate(entries.length, (int i) => i)
    ..sort((int a, int b) {
      final int byKey = compare(entries[a].$2, entries[b].$2);
      return byKey != 0 ? byKey : a.compareTo(b);
    });
  return <(EvaluationInput, List<FieldValue?>)>[
    for (final int i in order) entries[i],
  ];
}
