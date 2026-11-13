// Seeded generators of whole pipelines over a known set of documents, and
// the comparison of the local pipeline executor with a backend.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/pipeline_executor.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart'
    show PipelineEncoder;

import 'property.dart';
import 'property_pipeline.dart';

/// Where the generated pipelines read: a collection of documents with a
/// unique `o`, and documents of a subcollection with an id of its own.
class PipelineData {
  PipelineData(this.collection, this.subcollectionId, this.run);

  /// The path of the collection.
  final String collection;

  /// The id of the subcollections (under some of the documents of
  /// [collection]).
  final String subcollectionId;

  /// The value of the field `run` of every document, so that a pipeline over
  /// the whole database can keep only these.
  final String run;

  /// Path to data, in the order they were written.
  final Map<String, Map<String, Object?>> documents =
      <String, Map<String, Object?>>{};
}

/// A generated pipeline and what the comparison needs to know about it.
class GeneratedPipeline {
  GeneratedPipeline(this.pipeline, this.description, this.ordered);

  final Pipeline pipeline;

  /// The stages, readable.
  final String description;

  /// Whether the order of the results is defined: the results are compared
  /// in order, not as a multiset.
  final bool ordered;
}

/// What the generator knows about the rows after a stage.
class _State {
  /// The top-level fields the rows (may) have.
  Set<String> fields = <String>{};

  /// Fields that together tell the rows apart, or null when that is not
  /// known.
  List<String>? key = <String>['o'];

  /// Whether the order of the rows is defined.
  bool ordered = false;

  /// Whether a `sort` with the [key] made the order total, so that limit and
  /// offset select a defined set.
  bool totallyOrdered = false;
}

const List<String> _documentFields = <String>[
  'n1', 'n2', 'k1', 'f1', 'f2', 'i32', 'dec', 's1', 's2', 'b1', 't1', 't2', //
  'a1', 'a2', 'na1', 'sa1', 'm1', 'm2', 'ts1', 'ts2', 'v1', 'v2', 'nul', 'o',
];

const List<String> _aliases = <String>['x', 'y', 'z', 'n1', 's1', 'm1'];

extension PipelineStageGen on Gen {
  /// A document of [PipelineData]: [pipelineDocument] with `o` and `run`.
  Map<String, Object?> stageDocument(int o, String run) => <String, Object?>{
    ...pipelineDocument(),
    'o': o,
    'run': run,
  };

  /// A pipeline over [data] of 1 to [maxStages] stages after the source.
  GeneratedPipeline stagePipeline(
    PipelineSource source,
    PipelineData data, {
    int maxStages = 4,
  }) {
    final _State state = _State()..fields = _documentFields.toSet();
    final List<String> described = <String>[];
    Pipeline pipeline;
    final int roll = below(100);
    if (roll < 60) {
      pipeline = source.collection(data.collection);
      described.add('collection');
    } else if (roll < 75) {
      pipeline = source.collectionGroup(data.subcollectionId);
      described.add('collection_group');
    } else if (roll < 85) {
      pipeline = source.database().where(field('run').equal(data.run));
      described.add('database | where(run)');
    } else {
      final List<String> paths = data.documents.keys.toList();
      pipeline = source.documents(
        <String>[
          for (int i = between(1, 4); i > 0; i--) pick(paths),
          '${data.collection}/missing',
        ].toSet().toList(),
      );
      described.add('documents');
    }
    for (int i = between(1, maxStages); i > 0; i--) {
      final (Pipeline next, String text) = _stage(
        pipeline,
        source,
        data,
        state,
      );
      pipeline = next;
      described.add(text);
    }
    return GeneratedPipeline(pipeline, described.join(' | '), state.ordered);
  }

  (Pipeline, String) _stage(
    Pipeline pipeline,
    PipelineSource source,
    PipelineData data,
    _State state,
  ) {
    final int roll = below(100);
    if (roll < 18) {
      final BooleanExpression condition = chance(50)
          ? _comparison(state)
          : expression(Kind.bool, 2).asBoolean();
      return (pipeline.where(condition), 'where($condition)');
    }
    if (roll < 28) {
      return _sort(pipeline, state);
    }
    if (roll < 36 && state.totallyOrdered) {
      final int count = between(0, 5);
      if (chance(50)) {
        return (pipeline.limit(count), 'limit($count)');
      }
      return (pipeline.offset(count), 'offset($count)');
    }
    if (roll < 44) {
      final List<Selectable> selected = _selectables(state, between(1, 3));
      for (final String key in state.key ?? const <String>[]) {
        if (!selected.any((Selectable s) => s.alias == key)) {
          selected.add(field(key));
        }
      }
      state.fields = selected
          .map((Selectable s) => s.alias.split('.').first)
          .toSet();
      return (pipeline.select(selected), 'select($selected)');
    }
    if (roll < 52) {
      final List<Selectable> added = _selectables(state, between(1, 2))
          .where(
            (Selectable s) => !(state.key ?? const <String>[]).contains(
              s.alias.split('.').first,
            ),
          )
          .toList();
      if (added.isEmpty) {
        return (pipeline, '');
      }
      state.fields.addAll(
        added.map((Selectable s) => s.alias.split('.').first),
      );
      return (pipeline.addFields(added), 'addFields($added)');
    }
    if (roll < 57) {
      final List<String> removable = state.fields
          .where((String f) => !(state.key ?? const <String>[]).contains(f))
          .toList();
      if (removable.isEmpty) {
        return (pipeline, '');
      }
      final List<Object> removed = <Object>{
        for (int i = between(1, 2); i > 0; i--)
          chance(15) ? '${pick(removable)}.k' : pick(removable),
      }.toList();
      state.fields.removeAll(removed);
      return (pipeline.removeFields(removed), 'removeFields($removed)');
    }
    if (roll < 64) {
      final List<Selectable> groups = _groups(state, between(1, 2));
      state
        ..fields = groups.map((Selectable s) => s.alias).toSet()
        ..key = groups.map((Selectable s) => s.alias).toList()
        ..ordered = false
        ..totallyOrdered = false;
      return (pipeline.distinct(groups), 'distinct($groups)');
    }
    if (roll < 74) {
      final List<Selectable> groups = chance(40)
          ? <Selectable>[]
          : _groups(state, between(1, 2));
      final Set<String> names = groups.map((Selectable s) => s.alias).toSet();
      final List<AliasedAggregate> accumulators = <AliasedAggregate>[];
      for (int i = between(1, 3); i > 0; i--) {
        final String name = 'r$i';
        if (names.add(name)) {
          accumulators.add(_accumulator(state).as(name));
        }
      }
      if (accumulators.isEmpty) {
        names.add('cnt');
        accumulators.add(AggregateFunction('count').as('cnt'));
      }
      state
        ..fields = names
        ..key = groups.map((Selectable s) => s.alias).toList()
        ..ordered = false
        ..totallyOrdered = false;
      return (
        pipeline.aggregate(accumulators, groups: groups),
        'aggregate($accumulators, groups: $groups)',
      );
    }
    if (roll < 80) {
      final String alias = pick(const <String>['u', 'a1', 'x']);
      if ((state.key ?? const <String>[]).contains(alias)) {
        return (pipeline, '');
      }
      final Expression array = chance(70)
          ? field(pick(const <String>['a1', 'a2', 'na1', 'sa1', 'm1', 'zz']))
          : expression(Kind.arr, 1);
      state.fields.addAll(<String>[alias, 'ui']);
      state.key = state.key == null ? null : <String>[...state.key!, 'ui'];
      return (
        pipeline.unnest(array.as(alias), indexField: 'ui'),
        'unnest(${array.as(alias)}, indexField: ui)',
      );
    }
    if (roll < 85) {
      final Pipeline other = source
          .collection(data.collection)
          .where(_comparison(state));
      state
        ..fields.addAll(_documentFields)
        ..key = null
        ..ordered = false
        ..totallyOrdered = false;
      return (pipeline.union(other), 'union(${other.stages.length} stages)');
    }
    if (roll < 90) {
      final Expression map = chance(60)
          ? field(pick(const <String>['m1', 'm2', 'n1', 'zz']))
          : FunctionExpression('map', <Object?>[
              'o',
              field('o'),
              'w',
              expression(Kind.any, 1),
            ]);
      state
        ..fields = <String>{'o', 'w', 'a', 'b', 'c'}
        ..key = null
        ..ordered = false
        ..totallyOrdered = false;
      return (pipeline.replaceWith(map), 'replaceWith($map)');
    }
    if (roll < 95) {
      final String vectorField = pick(const <String>['v1', 'v2']);
      final List<double> query = <double>[
        for (int i = pick(const <int>[2, 3]); i > 0; i--) between(-12, 12) / 4,
      ];
      final DistanceMeasure measure = pick(DistanceMeasure.values);
      state
        ..fields.add('dist')
        ..ordered = false
        ..totallyOrdered = false;
      return (
        pipeline.findNearest(
          vectorField,
          query,
          measure,
          distanceField: 'dist',
        ),
        'findNearest($vectorField, $query, $measure, distanceField: dist)',
      );
    }
    return _sort(pipeline, state);
  }

  (Pipeline, String) _sort(Pipeline pipeline, _State state) {
    final List<Ordering> orderings = <Ordering>[
      for (int i = between(1, 2); i > 0; i--)
        (chance(70) ? field(_anyField(state)) : expression(Kind.any, 1)).let(
          (Expression e) => chance(50) ? e.ascending() : e.descending(),
        ),
    ];
    final List<String>? key = state.key;
    if (key != null) {
      orderings.addAll(key.map((String k) => field(k).ascending()));
    }
    state
      ..ordered = key != null
      ..totallyOrdered = key != null;
    return (pipeline.sort(orderings), 'sort($orderings)');
  }

  /// One of the fields the rows have, or a missing one.
  String _anyField(_State state) =>
      state.fields.isEmpty || chance(5) ? 'zz' : pick(state.fields.toList());

  BooleanExpression _comparison(_State state) {
    final Expression left = field(_anyField(state));
    final Object? right = chance(70)
        ? valueOfKind(pick(const <Kind>[Kind.num, Kind.str, Kind.bool]))
        : field(_anyField(state));
    return switch (below(5)) {
      0 => left.equal(right),
      1 => left.greaterThan(right),
      2 => left.lessThanOrEqual(right),
      3 => left.notEqual(right),
      _ => left.exists(),
    };
  }

  List<Selectable> _selectables(_State state, int count) {
    final Map<String, Selectable> result = <String, Selectable>{};
    for (int i = 0; i < count; i++) {
      final Selectable selectable;
      if (chance(50)) {
        selectable = field(_anyField(state));
      } else {
        String alias = pick(_aliases);
        if (chance(15)) {
          alias = '$alias.k';
        }
        selectable = expression(Kind.any, 1).as(alias);
      }
      final String root = selectable.alias.split('.').first;
      // A path and a path inside it are rejected.
      if (result.keys.any((String a) => a.split('.').first == root)) {
        continue;
      }
      result[selectable.alias] = selectable;
    }
    return result.values.toList();
  }

  List<Selectable> _groups(_State state, int count) {
    final Map<String, Selectable> result = <String, Selectable>{};
    for (int i = 0; i < count; i++) {
      final Selectable selectable = chance(70)
          ? field(_anyField(state))
          : expression(Kind.any, 1).as(pick(const <String>['g', 'h']));
      if (selectable.alias.contains('.')) {
        continue;
      }
      result[selectable.alias] = selectable;
    }
    return result.isEmpty ? <Selectable>[field('o')] : result.values.toList();
  }

  AggregateFunction _accumulator(_State state) {
    final Expression argument = chance(70)
        ? field(_anyField(state))
        : expression(Kind.num, 1);
    final List<String> names = <String>[
      'count', 'sum', 'average', 'minimum', 'maximum', 'count_distinct', //
      if (state.totallyOrdered) ...<String>['first', 'last', 'array_agg'],
    ];
    final String name = pick(<String>[...names, 'count_if']);
    if (name == 'count_if') {
      return AggregateFunction(name, <Object?>[_comparison(state)]);
    }
    if (name == 'count' && chance(30)) {
      return AggregateFunction(name);
    }
    return AggregateFunction(name, <Object?>[argument]);
  }
}

extension<T> on T {
  R let<R>(R Function(T value) body) => body(this);
}

/// One result of a pipeline, comparable: the document it still is (or
/// null) and its fields.
class PipelineRow {
  PipelineRow(this.key, this.fields);

  final String? key;
  final model.ObjectValue fields;

  @override
  String toString() => '${key ?? '-'}${describeValue(fields)}';
}

/// Runs generated pipelines locally.
class LocalPipelines {
  LocalPipelines(this.databaseId)
    : _encoder = PipelineEncoder(databaseId),
      _local = LocalEvaluation(databaseId),
      executor = PipelineExecutor(databaseId);

  final DatabaseId databaseId;
  final PipelineEncoder _encoder;
  final LocalEvaluation _local;
  final PipelineExecutor executor;

  model.FieldValue toModel(Object? value) => _local.toModel(value);

  /// The rows of [pipeline] over [documents] (path to data).
  ///
  /// Throws a [PipelineFailure] or an [UnsupportedExpression] like
  /// [PipelineExecutor.execute].
  List<PipelineRow> run(
    Pipeline pipeline,
    Map<String, Map<String, Object?>> documents,
  ) {
    final List<EvaluationInput> inputs = <EvaluationInput>[
      for (final MapEntry<String, Map<String, Object?>> document
          in documents.entries)
        EvaluationInput(
          toModel(document.value) as model.ObjectValue,
          key: DocumentKey.fromPathString(document.key),
        ),
    ];
    // ignore: invalid_use_of_internal_member
    final List<EvaluationInput> rows = executor.execute(
      // ignore: invalid_use_of_internal_member
      pipeline.toProto(_encoder),
      inputs,
    );
    return <PipelineRow>[
      for (final EvaluationInput row in rows)
        PipelineRow(row.key?.path.canonicalString, row.fields),
    ];
  }

  /// The row of a result of the backend.
  PipelineRow remoteRow(PipelineResult result) => PipelineRow(
    result.ref?.path,
    toModel(result.data()) as model.ObjectValue,
  );
}

/// Whether two rows are the same. With [loose] numbers are compared by value
/// (1 is 1.0): for the values a group shows, which of equal values that is
/// is not specified.
bool sameRow(PipelineRow local, PipelineRow remote, {bool loose = false}) {
  if (local.key != remote.key) {
    return false;
  }
  return loose
      ? local.fields.compareTo(remote.fields) == 0
      : sameValue(local.fields, remote.fields);
}

/// Whether [local] and [remote] have the same rows: in the same order when
/// [ordered], else in any order.
bool sameRows(
  List<PipelineRow> local,
  List<PipelineRow> remote, {
  required bool ordered,
  bool loose = false,
}) {
  if (local.length != remote.length) {
    return false;
  }
  if (ordered) {
    for (int i = 0; i < local.length; i++) {
      if (!sameRow(local[i], remote[i], loose: loose)) {
        return false;
      }
    }
    return true;
  }
  final List<PipelineRow> rest = List<PipelineRow>.of(remote);
  for (final PipelineRow row in local) {
    final int index = rest.indexWhere(
      (PipelineRow other) => sameRow(row, other, loose: loose),
    );
    if (index < 0) {
      return false;
    }
    rest.removeAt(index);
  }
  return true;
}

/// The rows of [local] and [remote] that the other side does not have, one
/// per line, for a report.
String describeRowDifference(
  List<PipelineRow> local,
  List<PipelineRow> remote, {
  required bool ordered,
}) {
  final List<PipelineRow> onlyRemote = List<PipelineRow>.of(remote);
  final List<PipelineRow> onlyLocal = <PipelineRow>[];
  for (final PipelineRow row in local) {
    final int index = onlyRemote.indexWhere(
      (PipelineRow other) => sameRow(row, other),
    );
    if (index < 0) {
      onlyLocal.add(row);
    } else {
      onlyRemote.removeAt(index);
    }
  }
  final StringBuffer out = StringBuffer(
    '${local.length} rows locally, ${remote.length} on the emulator',
  );
  if (onlyLocal.isEmpty && onlyRemote.isEmpty && ordered) {
    out
      ..write('; the same rows in another order:\n      local  ')
      ..write(local.map(_short).join('\n             '))
      ..write('\n      remote ')
      ..write(remote.map(_short).join('\n             '));
    return out.toString();
  }
  // Rows of the same document: only the fields that differ.
  for (final PipelineRow row in List<PipelineRow>.of(onlyLocal)) {
    if (row.key == null) {
      continue;
    }
    final int index = onlyRemote.indexWhere(
      (PipelineRow other) => other.key == row.key,
    );
    if (index < 0) {
      continue;
    }
    final PipelineRow other = onlyRemote.removeAt(index);
    onlyLocal.remove(row);
    final Set<String> names = <String>{
      for (final MapEntry<String, model.FieldValue> e
          in row.fields.internalValue)
        e.key,
      for (final MapEntry<String, model.FieldValue> e
          in other.fields.internalValue)
        e.key,
    };
    out.write('\n      ${row.key!.split('/').skip(1).join('/')}:');
    for (final String name in names) {
      final model.FieldValue? l = row.fields.internalValue[name];
      final model.FieldValue? r = other.fields.internalValue[name];
      if (l == null || r == null || !sameValue(l, r)) {
        out.write(
          '\n        $name: local ${l == null ? 'missing' : describeValue(l)}, '
          'remote ${r == null ? 'missing' : describeValue(r)}',
        );
      }
    }
  }
  for (final PipelineRow row in onlyLocal) {
    out.write('\n      only local  ${_short(row)}');
  }
  for (final PipelineRow row in onlyRemote) {
    out.write('\n      only remote ${_short(row)}');
  }
  return out.toString();
}

String _short(PipelineRow row) {
  final String key = row.key == null
      ? '-'
      : row.key!.split('/').skip(1).join('/');
  final String fields = row.fields.internalValue
      .map(
        (MapEntry<String, model.FieldValue> e) =>
            '${e.key}: ${describeValue(e.value)}',
      )
      .join(', ');
  final String text = '$key {$fields}';
  return text.length > 400 ? '${text.substring(0, 400)}...' : text;
}
