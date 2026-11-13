// Seeded generators of documents and pipeline expressions, and the
// comparison of the local expression evaluator with a backend
// (`select(expression)` on the Enterprise edition emulator).

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/aggregate_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart'
    show PipelineEncoder;
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;

import 'property.dart';

/// The kinds of values the generator tells apart.
enum Kind {
  num,
  int,
  small,
  str,
  bytes,
  bool,
  arr,
  numArr,
  strArr,
  map,
  ts,
  vec,
  ref,
  any,
}

/// A function the generator knows: its name, what it returns and what its
/// arguments should be. [more] is the kind of optional further arguments.
class Fn {
  const Fn(this.name, this.returns, this.args, {this.more, this.literals});

  final String name;
  final Kind returns;
  final List<Kind> args;
  final Kind? more;

  /// For an argument that has to be a literal from a list (a unit, a type
  /// name): the index of the argument and the list.
  final Map<int, List<String>>? literals;
}

const List<String> _units = <String>[
  'microsecond', 'millisecond', 'second', 'minute', 'hour', 'day', //
];
const List<String> _truncUnits = <String>[
  ..._units, 'week', 'isoweek', 'month', 'quarter', 'year', 'isoyear', //
];
const List<String> _extractParts = <String>[
  'microsecond', 'millisecond', 'second', 'minute', 'hour', 'day', //
  'dayofweek', 'dayofyear', 'week', 'isoweek', 'month', 'quarter', 'year',
  'isoyear',
];
const List<String> _typeNames = <String>[
  'null', 'array', 'boolean', 'bytes', 'timestamp', 'geo_point', 'number', //
  'int32', 'int64', 'float64', 'decimal128', 'map', 'reference', 'string',
  'vector',
];

/// Every function the local evaluator implements, except the ones without a
/// repeatable result (`rand`, `current_timestamp`) and the ones that take a
/// lambda (generated separately).
const List<Fn> functionCatalog = <Fn>[
  Fn('equal', Kind.bool, <Kind>[Kind.any, Kind.any]),
  Fn('not_equal', Kind.bool, <Kind>[Kind.any, Kind.any]),
  Fn('less_than', Kind.bool, <Kind>[Kind.any, Kind.any]),
  Fn('less_than_or_equal', Kind.bool, <Kind>[Kind.any, Kind.any]),
  Fn('greater_than', Kind.bool, <Kind>[Kind.any, Kind.any]),
  Fn('greater_than_or_equal', Kind.bool, <Kind>[Kind.any, Kind.any]),
  Fn('equal_any', Kind.bool, <Kind>[Kind.any, Kind.arr]),
  Fn('not_equal_any', Kind.bool, <Kind>[Kind.any, Kind.arr]),
  Fn('and', Kind.bool, <Kind>[Kind.bool, Kind.bool], more: Kind.bool),
  Fn('or', Kind.bool, <Kind>[Kind.bool, Kind.bool], more: Kind.bool),
  Fn('nor', Kind.bool, <Kind>[Kind.bool, Kind.bool], more: Kind.bool),
  Fn('xor', Kind.bool, <Kind>[Kind.bool, Kind.bool], more: Kind.bool),
  Fn('not', Kind.bool, <Kind>[Kind.bool]),
  Fn('conditional', Kind.any, <Kind>[Kind.bool, Kind.any, Kind.any]),
  Fn('switch_on', Kind.any, <Kind>[
    Kind.bool,
    Kind.any,
    Kind.bool,
    Kind.any,
    Kind.any,
  ]),
  Fn('maximum', Kind.any, <Kind>[Kind.any, Kind.any], more: Kind.any),
  Fn('minimum', Kind.any, <Kind>[Kind.any, Kind.any], more: Kind.any),
  Fn('maximum', Kind.any, <Kind>[Kind.arr]),
  Fn('minimum', Kind.any, <Kind>[Kind.arr]),
  Fn('is_error', Kind.bool, <Kind>[Kind.any]),
  Fn('if_error', Kind.any, <Kind>[Kind.any, Kind.any]),
  Fn('if_absent', Kind.any, <Kind>[Kind.any, Kind.any]),
  Fn('if_null', Kind.any, <Kind>[Kind.any, Kind.any]),
  Fn('coalesce', Kind.any, <Kind>[Kind.any, Kind.any], more: Kind.any),
  Fn('type', Kind.str, <Kind>[Kind.any]),
  Fn(
    'is_type',
    Kind.bool,
    <Kind>[Kind.any, Kind.str],
    literals: <int, List<String>>{1: _typeNames},
  ),
  Fn('array', Kind.arr, <Kind>[Kind.any], more: Kind.any),
  Fn('document_id', Kind.str, <Kind>[Kind.ref]),
  Fn('collection_id', Kind.str, <Kind>[Kind.ref]),
  Fn('parent', Kind.ref, <Kind>[Kind.ref]),
  // Arithmetic.
  Fn('add', Kind.num, <Kind>[Kind.num, Kind.num]),
  Fn('subtract', Kind.num, <Kind>[Kind.num, Kind.num]),
  Fn('multiply', Kind.num, <Kind>[Kind.num, Kind.num]),
  Fn('divide', Kind.num, <Kind>[Kind.num, Kind.num]),
  Fn('mod', Kind.num, <Kind>[Kind.num, Kind.num]),
  Fn('abs', Kind.num, <Kind>[Kind.num]),
  Fn('ceil', Kind.num, <Kind>[Kind.num]),
  Fn('floor', Kind.num, <Kind>[Kind.num]),
  Fn('round', Kind.num, <Kind>[Kind.num]),
  Fn('round', Kind.num, <Kind>[Kind.num, Kind.small]),
  Fn('trunc', Kind.num, <Kind>[Kind.num]),
  Fn('trunc', Kind.num, <Kind>[Kind.num, Kind.small]),
  Fn('sqrt', Kind.num, <Kind>[Kind.num]),
  Fn('pow', Kind.num, <Kind>[Kind.num, Kind.num]),
  Fn('exp', Kind.num, <Kind>[Kind.num]),
  Fn('ln', Kind.num, <Kind>[Kind.num]),
  Fn('log', Kind.num, <Kind>[Kind.num, Kind.num]),
  Fn('log10', Kind.num, <Kind>[Kind.num]),
  // Strings and bytes.
  Fn('char_length', Kind.int, <Kind>[Kind.str]),
  Fn('byte_length', Kind.int, <Kind>[Kind.str]),
  Fn('byte_length', Kind.int, <Kind>[Kind.bytes]),
  Fn('length', Kind.int, <Kind>[Kind.any]),
  Fn('to_lower', Kind.str, <Kind>[Kind.str]),
  Fn('to_upper', Kind.str, <Kind>[Kind.str]),
  Fn('to_upper', Kind.bytes, <Kind>[Kind.bytes]),
  Fn('trim', Kind.str, <Kind>[Kind.str]),
  Fn('trim', Kind.str, <Kind>[Kind.str, Kind.str]),
  Fn('trim', Kind.bytes, <Kind>[Kind.bytes]),
  Fn('ltrim', Kind.str, <Kind>[Kind.str]),
  Fn('ltrim', Kind.str, <Kind>[Kind.str, Kind.str]),
  Fn('rtrim', Kind.str, <Kind>[Kind.str]),
  Fn('rtrim', Kind.str, <Kind>[Kind.str, Kind.str]),
  Fn('reverse', Kind.str, <Kind>[Kind.str]),
  Fn('reverse', Kind.arr, <Kind>[Kind.arr]),
  Fn('reverse', Kind.bytes, <Kind>[Kind.bytes]),
  Fn('string_reverse', Kind.str, <Kind>[Kind.str]),
  Fn('substring', Kind.str, <Kind>[Kind.str, Kind.small]),
  Fn('substring', Kind.str, <Kind>[Kind.str, Kind.small, Kind.small]),
  Fn('substring', Kind.bytes, <Kind>[Kind.bytes, Kind.small, Kind.small]),
  Fn('concat', Kind.str, <Kind>[Kind.str, Kind.str], more: Kind.str),
  Fn('concat', Kind.arr, <Kind>[Kind.arr, Kind.arr]),
  Fn('concat', Kind.bytes, <Kind>[Kind.bytes, Kind.bytes]),
  Fn('string_concat', Kind.str, <Kind>[Kind.str, Kind.str], more: Kind.str),
  Fn('starts_with', Kind.bool, <Kind>[Kind.str, Kind.str]),
  Fn('ends_with', Kind.bool, <Kind>[Kind.str, Kind.str]),
  Fn('string_contains', Kind.bool, <Kind>[Kind.str, Kind.str]),
  Fn(
    'like',
    Kind.bool,
    <Kind>[Kind.str, Kind.str],
    literals: <int, List<String>>{
      1: <String>['a%', '%b', '_', '%', 'a_', '%a%b%', r'\%', 'é%', ''],
    },
  ),
  Fn(
    'regex_contains',
    Kind.bool,
    <Kind>[Kind.str, Kind.str],
    literals: <int, List<String>>{1: _patterns},
  ),
  Fn(
    'regex_match',
    Kind.bool,
    <Kind>[Kind.str, Kind.str],
    literals: <int, List<String>>{1: _patterns},
  ),
  Fn(
    'regex_find',
    Kind.str,
    <Kind>[Kind.str, Kind.str],
    literals: <int, List<String>>{1: _patterns},
  ),
  Fn(
    'regex_find_all',
    Kind.strArr,
    <Kind>[Kind.str, Kind.str],
    literals: <int, List<String>>{1: _patterns},
  ),
  Fn('split', Kind.strArr, <Kind>[Kind.str, Kind.str]),
  Fn('join', Kind.str, <Kind>[Kind.strArr, Kind.str]),
  Fn('string_replace_all', Kind.str, <Kind>[Kind.str, Kind.str, Kind.str]),
  Fn('string_replace_one', Kind.str, <Kind>[Kind.str, Kind.str, Kind.str]),
  Fn('string_repeat', Kind.str, <Kind>[Kind.str, Kind.small]),
  Fn('string_index_of', Kind.int, <Kind>[Kind.str, Kind.str]),
  // Arrays.
  Fn('array_length', Kind.int, <Kind>[Kind.arr]),
  Fn('array_contains', Kind.bool, <Kind>[Kind.arr, Kind.any]),
  Fn('array_contains_any', Kind.bool, <Kind>[Kind.arr, Kind.arr]),
  Fn('array_contains_all', Kind.bool, <Kind>[Kind.arr, Kind.arr]),
  Fn('array_reverse', Kind.arr, <Kind>[Kind.arr]),
  Fn('array_get', Kind.any, <Kind>[Kind.arr, Kind.small]),
  Fn('array_slice', Kind.arr, <Kind>[Kind.arr, Kind.small]),
  Fn('array_slice', Kind.arr, <Kind>[Kind.arr, Kind.small, Kind.small]),
  Fn('array_first', Kind.any, <Kind>[Kind.arr]),
  Fn('array_last', Kind.any, <Kind>[Kind.arr]),
  Fn('array_first_n', Kind.arr, <Kind>[Kind.arr, Kind.small]),
  Fn('array_last_n', Kind.arr, <Kind>[Kind.arr, Kind.small]),
  Fn(
    'array_index_of',
    Kind.int,
    <Kind>[Kind.arr, Kind.any, Kind.str],
    literals: <int, List<String>>{
      2: <String>['first', 'last'],
    },
  ),
  Fn('array_index_of_all', Kind.numArr, <Kind>[Kind.arr, Kind.any]),
  Fn('maximum_n', Kind.arr, <Kind>[Kind.arr, Kind.small]),
  Fn('minimum_n', Kind.arr, <Kind>[Kind.arr, Kind.small]),
  Fn('array_concat', Kind.arr, <Kind>[Kind.arr, Kind.arr], more: Kind.arr),
  Fn('sum', Kind.num, <Kind>[Kind.numArr]),
  // Maps.
  Fn(
    'map_get',
    Kind.any,
    <Kind>[Kind.map, Kind.str],
    literals: <int, List<String>>{
      1: <String>['a', 'b', 'c', 'zz'],
    },
  ),
  Fn(
    'get_field',
    Kind.any,
    <Kind>[Kind.any, Kind.str],
    literals: <int, List<String>>{
      1: <String>['a', 'b', 'c', 'zz'],
    },
  ),
  Fn('map_keys', Kind.strArr, <Kind>[Kind.map]),
  Fn('map_values', Kind.arr, <Kind>[Kind.map]),
  Fn('map_entries', Kind.arr, <Kind>[Kind.map]),
  Fn('map_merge', Kind.map, <Kind>[Kind.map, Kind.map], more: Kind.map),
  Fn(
    'map_remove',
    Kind.map,
    <Kind>[Kind.map, Kind.str],
    literals: <int, List<String>>{
      1: <String>['a', 'b', 'zz'],
    },
  ),
  Fn(
    'map_set',
    Kind.map,
    <Kind>[Kind.map, Kind.str, Kind.any],
    literals: <int, List<String>>{
      1: <String>['a', 'b', 'zz'],
    },
  ),
  Fn(
    'map_set',
    Kind.map,
    <Kind>[Kind.map, Kind.str, Kind.any, Kind.str, Kind.any],
    literals: <int, List<String>>{
      1: <String>['a', 'b', 'zz'],
      3: <String>['a', 'c', 'zz'],
    },
  ),
  // Timestamps.
  Fn(
    'timestamp_add',
    Kind.ts,
    <Kind>[Kind.ts, Kind.str, Kind.int],
    literals: <int, List<String>>{1: _units},
  ),
  Fn(
    'timestamp_subtract',
    Kind.ts,
    <Kind>[Kind.ts, Kind.str, Kind.int],
    literals: <int, List<String>>{1: _units},
  ),
  Fn(
    'timestamp_diff',
    Kind.int,
    <Kind>[Kind.ts, Kind.ts, Kind.str],
    literals: <int, List<String>>{2: _units},
  ),
  Fn(
    'timestamp_trunc',
    Kind.ts,
    <Kind>[Kind.ts, Kind.str],
    literals: <int, List<String>>{1: _truncUnits},
  ),
  Fn(
    'timestamp_extract',
    Kind.int,
    <Kind>[Kind.ts, Kind.str],
    literals: <int, List<String>>{1: _extractParts},
  ),
  Fn('timestamp_to_unix_micros', Kind.int, <Kind>[Kind.ts]),
  Fn('timestamp_to_unix_millis', Kind.int, <Kind>[Kind.ts]),
  Fn('timestamp_to_unix_seconds', Kind.int, <Kind>[Kind.ts]),
  Fn('unix_micros_to_timestamp', Kind.ts, <Kind>[Kind.int]),
  Fn('unix_millis_to_timestamp', Kind.ts, <Kind>[Kind.int]),
  Fn('unix_seconds_to_timestamp', Kind.ts, <Kind>[Kind.int]),
  // Vectors.
  Fn('cosine_distance', Kind.num, <Kind>[Kind.vec, Kind.vec]),
  Fn('dot_product', Kind.num, <Kind>[Kind.vec, Kind.vec]),
  Fn('euclidean_distance', Kind.num, <Kind>[Kind.vec, Kind.vec]),
  Fn('vector_length', Kind.int, <Kind>[Kind.vec]),
];

const List<String> _patterns = <String>[
  'a', 'a+', '^a', 'b\$', 'a.b', '[ab]+', '(a)b', 'a|b', '.', '', 'é', //
  r'\d+', '(',
];

/// The fields of the generated documents, by kind. Every document has a
/// value, null or nothing in each of them.
const Map<Kind, List<String>> fieldsOfKind = <Kind, List<String>>{
  Kind.num: <String>['n1', 'n2', 'f1', 'f2', 'i32', 'dec'],
  Kind.int: <String>['n1', 'n2'],
  Kind.small: <String>['k1'],
  Kind.str: <String>['s1', 's2'],
  Kind.bytes: <String>['b1'],
  Kind.bool: <String>['t1', 't2'],
  Kind.arr: <String>['a1', 'a2', 'na1'],
  Kind.numArr: <String>['na1'],
  Kind.strArr: <String>['sa1'],
  Kind.map: <String>['m1', 'm2'],
  Kind.ts: <String>['ts1', 'ts2'],
  Kind.vec: <String>['v1', 'v2'],
  Kind.ref: <String>['__name__'],
};

/// The generators of this file, on top of the value generators of [Gen].
extension PipelineGen on Gen {
  String word() {
    final StringBuffer buffer = StringBuffer();
    for (int i = below(5); i > 0; i--) {
      buffer.write(
        pick(const <String>[
          'a',
          'b',
          'ab',
          'A',
          ' ',
          'é',
          '😀',
          'ß',
          '.',
          '0',
          '%',
          '_',
        ]),
      );
    }
    return buffer.toString();
  }

  /// A plain value of [kind] (never an expression).
  Object? valueOfKind(Kind kind, {bool insideArray = false}) {
    switch (kind) {
      case Kind.num:
        switch (below(6)) {
          case 0:
            return float();
          case 1:
            return Int32Value(between(-9, 9));
          case 2:
            return Decimal128Value(
              pick(const <String>[
                '0',
                '1',
                '-1',
                '1.5',
                '2.5',
                '-2.5',
                '0.1',
                '3',
                '20',
                '1E+3',
                'NaN',
                'Infinity',
                '100.25',
              ]),
            );
          case 3:
            return between(-9, 9) / 2;
          default:
            return chance(70) ? between(-20, 20) : integer();
        }
      case Kind.int:
        return chance(75) ? between(-20, 20) : integer();
      case Kind.small:
        return between(-2, 6);
      case Kind.str:
        return word();
      case Kind.bytes:
        return Blob(
          Uint8List.fromList(<int>[
            for (int i = below(5); i > 0; i--)
              pick(const <int>[0, 32, 65, 97, 98, 122, 128, 255]),
          ]),
        );
      case Kind.bool:
        return chance(50);
      case Kind.arr:
        return <Object?>[
          for (int i = below(5); i > 0; i--)
            valueOfKind(
              pick(const <Kind>[
                Kind.int,
                Kind.int,
                Kind.str,
                Kind.num,
                Kind.bool,
                Kind.any,
              ]),
              insideArray: true,
            ),
        ];
      case Kind.numArr:
        return <Object?>[for (int i = below(5); i > 0; i--) between(-5, 5)];
      case Kind.strArr:
        return <Object?>[
          for (int i = below(5); i > 0; i--) chance(85) ? word() : null,
        ];
      case Kind.map:
        return <String, Object?>{
          for (int i = below(4); i > 0; i--)
            pick(const <String>['a', 'b', 'c']): valueOfKind(
              pick(const <Kind>[Kind.int, Kind.str, Kind.any]),
            ),
        };
      case Kind.ts:
        return timestamp();
      case Kind.vec:
        return VectorValue(<double>[
          for (int i = chance(85) ? 3 : 2; i > 0; i--)
            between(-3, 3).toDouble(),
        ]);
      case Kind.ref:
      case Kind.any:
        switch (below(9)) {
          case 0:
            return null;
          case 1:
            return double.nan;
          case 2:
            return geoPoint();
          case 3:
            // An array can not hold an array, nor a vector.
            return insideArray ? null : valueOfKind(Kind.arr);
          case 4:
            return valueOfKind(Kind.map);
          default:
            return valueOfKind(
              pick(<Kind>[
                Kind.num,
                Kind.int,
                Kind.str,
                Kind.bool,
                Kind.ts,
                Kind.bytes,
                if (!insideArray) Kind.vec,
              ]),
            );
        }
    }
  }

  /// A document with a value, null or nothing in each field of
  /// [fieldsOfKind].
  Map<String, Object?> pipelineDocument() {
    final Map<String, Object?> data = <String, Object?>{'nul': null};
    void put(String name, Object? Function() value) {
      final int roll = below(100);
      if (roll < 8) {
        data[name] = null;
      } else if (roll >= 16) {
        data[name] = value();
      }
    }

    put('n1', () => valueOfKind(Kind.int));
    put('n2', () => valueOfKind(Kind.int));
    put('k1', () => valueOfKind(Kind.small));
    put('f1', float);
    put('f2', () => between(-40, 40) / 4);
    put(
      'i32',
      () => Int32Value(
        chance(80)
            ? between(-50, 50)
            : pick(const <int>[2147483647, -2147483648]),
      ),
    );
    put(
      'dec',
      () => valueOfKind(Kind.num) is Decimal128Value
          ? Decimal128Value('1.5')
          : Decimal128Value(
              pick(const <String>[
                '0',
                '1',
                '-1',
                '1.5',
                '2.5',
                '0.1',
                '3',
                '100.25',
                'NaN',
                '1E+3',
              ]),
            ),
    );
    put('s1', word);
    put('s2', word);
    put('b1', () => valueOfKind(Kind.bytes));
    put('t1', () => chance(50));
    put('t2', () => chance(50));
    put('a1', () => valueOfKind(Kind.arr));
    put('a2', () => valueOfKind(Kind.arr));
    put('na1', () => valueOfKind(Kind.numArr));
    put('sa1', () => valueOfKind(Kind.strArr));
    put('m1', () => valueOfKind(Kind.map));
    put('m2', () => valueOfKind(Kind.map));
    put('ts1', timestamp);
    put('ts2', timestamp);
    put('v1', () => valueOfKind(Kind.vec));
    put('v2', () => valueOfKind(Kind.vec));
    return data;
  }

  /// An expression that should evaluate to [kind] (not always: some
  /// arguments are of another kind on purpose).
  Expression expression(Kind kind, int depth) {
    final Kind wanted = chance(6) ? Kind.any : kind;
    if (depth > 0 && chance(60)) {
      final List<Fn> candidates = functionCatalog
          .where((Fn f) => wanted == Kind.any || _fits(f.returns, wanted))
          .toList();
      if (candidates.isNotEmpty) {
        return call(pick(candidates), depth - 1);
      }
    }
    final List<String>? fields = wanted == Kind.any
        ? fieldsOfKind[pick(fieldsOfKind.keys.toList())]
        : fieldsOfKind[wanted];
    if (chance(8)) {
      return field(pick(const <String>['zz', 'nul']));
    }
    if (fields != null && chance(60)) {
      return field(pick(fields));
    }
    return constant(valueOfKind(wanted == Kind.ref ? Kind.any : wanted));
  }

  bool _fits(Kind returns, Kind wanted) {
    if (returns == wanted || returns == Kind.any) {
      return true;
    }
    return switch (wanted) {
      Kind.num => returns == Kind.int || returns == Kind.small,
      Kind.int => returns == Kind.small,
      Kind.arr => returns == Kind.numArr || returns == Kind.strArr,
      _ => false,
    };
  }

  /// A call of [function] with generated arguments.
  Expression call(Fn function, int depth) {
    final List<Expression> args = <Expression>[];
    for (int i = 0; i < function.args.length; i++) {
      final List<String>? literals = function.literals?[i];
      if (literals != null) {
        args.add(constant(pick(literals)));
      } else {
        args.add(expression(function.args[i], depth));
      }
    }
    final Kind? more = function.more;
    if (more != null) {
      for (int i = below(3); i > 0; i--) {
        args.add(expression(more, depth));
      }
    }
    return FunctionExpression(function.name, args);
  }

  /// A call of `array_filter` or `array_transform` with a small lambda.
  Expression lambda(int depth) {
    final Expression source = expression(Kind.arr, depth);
    final Expression e = variable('e');
    if (chance(50)) {
      final BooleanExpression condition = pick(<BooleanExpression Function()>[
        () => e.greaterThan(expression(Kind.int, 0)),
        () => e.equal(expression(Kind.any, 0)),
        () => e.isType(pick(_typeNames)),
        () => e.add(1).greaterThan(0),
        () => e.notEqual(null),
      ])();
      return FunctionExpression('array_filter', <Object?>[
        source,
        constant('e'),
        condition,
      ]);
    }
    if (chance(30)) {
      return FunctionExpression('array_transform', <Object?>[
        source,
        constant('e'),
        constant('i'),
        pick(<Expression Function()>[
          () => variable('i'),
          () => array(<Object?>[e, variable('i')]),
          () => e.equal(variable('i')),
        ])(),
      ]);
    }
    return FunctionExpression('array_transform', <Object?>[
      source,
      constant('e'),
      pick(<Expression Function()>[
        () => e.type(),
        () => e.ifNull(expression(Kind.any, 0)),
        () => e.multiply(2).ifError(e),
        () => e.equal(expression(Kind.any, 0)),
        () => expression(Kind.any, 0),
      ])(),
    ]);
  }

  /// A top-level expression.
  Expression pipelineExpression() {
    if (chance(6)) {
      return lambda(1);
    }
    return call(pick(functionCatalog), between(0, 2));
  }
}

/// Evaluates expressions locally for documents given as plain data.
class LocalEvaluation {
  LocalEvaluation(this.databaseId)
    : _converter = UserDataConverter(databaseId),
      _encoder = PipelineEncoder(databaseId),
      _serializer = RemoteSerializer(databaseId),
      _evaluator = ExpressionEvaluator(databaseId);

  final DatabaseId databaseId;
  final UserDataConverter _converter;
  final PipelineEncoder _encoder;
  final RemoteSerializer _serializer;
  final ExpressionEvaluator _evaluator;

  /// The model value of a plain Dart value. Unlike the converter of the SDK
  /// it accepts what only a pipeline result can hold: an array in an array.
  model.FieldValue toModel(Object? value) {
    if (value is List) {
      return model.ArrayValue.fromList(value.map(toModel).toList());
    } else if (value is Map) {
      return model.ObjectValue.fromMap(<String, model.FieldValue>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          entry.key! as String: toModel(entry.value),
      });
    }
    return _converter.parseQueryValue(value);
  }

  /// The aggregate [function] over [documents] (path to data), in their
  /// order.
  EvaluateResult aggregate(
    AggregateFunction function,
    Map<String, Map<String, Object?>> documents,
  ) {
    return AggregateEvaluator(
      _evaluator,
    ).aggregate(function.toProto(_encoder), <EvaluationInput>[
      for (final MapEntry<String, Map<String, Object?>> document
          in documents.entries)
        EvaluationInput(
          toModel(document.value) as model.ObjectValue,
          key: DocumentKey.fromPathString(document.key),
        ),
    ]);
  }

  /// A result as one line of text: `ERROR`, `UNSET`, or the value as a
  /// base64 encoded `google.firestore.v1.Value`.
  String encodeResult(EvaluateResult result) {
    final model.FieldValue? value = result.value;
    if (value == null) {
      return result.isError ? 'ERROR' : 'UNSET';
    }
    return base64.encode(_serializer.encodeValue(value).writeToBuffer());
  }

  /// The inverse of [encodeResult].
  EvaluateResult decodeResult(String text) {
    if (text == 'ERROR') {
      return EvaluateResult.error;
    } else if (text == 'UNSET') {
      return EvaluateResult.unset;
    }
    return EvaluateValue(
      _serializer.decodeValue(pb.Value.fromBuffer(base64.decode(text))),
    );
  }

  EvaluateResult evaluate(
    Expression expression,
    String documentPath,
    Map<String, Object?> data,
  ) {
    return _evaluator.evaluate(
      expression.toProto(_encoder),
      EvaluationInput(
        toModel(data) as model.ObjectValue,
        key: DocumentKey.fromPathString(documentPath),
      ),
    );
  }
}

/// How a value is shown in a mismatch report: with its type.
String describeValue(model.FieldValue value) =>
    '${value.runtimeType.toString().replaceAll('FieldValue', '').replaceAll('Value', '')}($value)';

String describeResult(EvaluateResult result) {
  final model.FieldValue? value = result.value;
  return value == null ? '$result' : describeValue(value);
}

/// Whether [local] and [remote] are the same value of the same type.
/// Doubles may differ in the last bits (the two sides use different math
/// libraries).
bool sameValue(model.FieldValue local, model.FieldValue remote) {
  if (local is model.ArrayValue && remote is model.ArrayValue) {
    if (local.internalValue.length != remote.internalValue.length) {
      return false;
    }
    for (int i = 0; i < local.internalValue.length; i++) {
      if (!sameValue(local.internalValue[i], remote.internalValue[i])) {
        return false;
      }
    }
    return true;
  }
  if (local is model.ObjectValue && remote is model.ObjectValue) {
    if (local.internalValue.length != remote.internalValue.length) {
      return false;
    }
    for (final MapEntry<String, model.FieldValue> entry
        in local.internalValue) {
      final model.FieldValue? other = remote.internalValue[entry.key];
      if (other == null || !sameValue(entry.value, other)) {
        return false;
      }
    }
    return true;
  }
  if (local.runtimeType != remote.runtimeType) {
    return false;
  }
  if (local is model.DoubleValue && remote is model.DoubleValue) {
    final double a = local.value;
    final double b = remote.value;
    if (a.isNaN || b.isNaN) {
      return a.isNaN && b.isNaN;
    }
    if (a == b) {
      // Also the same zero.
      return a.isNegative == b.isNegative;
    }
    if (a.isInfinite || b.isInfinite) {
      // An infinity is only itself (and the tolerance below would be one).
      return false;
    }
    final double scale = a.abs() > b.abs() ? a.abs() : b.abs();
    return (a - b).abs() <= scale * 1e-12;
  }
  if (local is model.TimestampValue && remote is model.TimestampValue) {
    return local.value.seconds == remote.value.seconds &&
        local.value.nanoseconds ~/ 1000 == remote.value.nanoseconds ~/ 1000;
  }
  return local.compareTo(remote) == 0;
}

/// A fixed value of each kind, for [edgeMatrix].
Object? _sample(Kind kind) {
  return switch (kind) {
    Kind.num => 2.5,
    Kind.int => 7,
    Kind.small => 2,
    Kind.str => 'abab',
    Kind.bytes => Blob(Uint8List.fromList(<int>[65, 98, 0])),
    Kind.bool => true,
    Kind.arr => <Object?>[3, 'a', null, 1.5],
    Kind.numArr => <Object?>[3, 1, 2],
    Kind.strArr => <Object?>['a', 'b'],
    Kind.map => <String, Object?>{'a': 1, 'b': 'x'},
    Kind.ts => const Timestamp(1700000000, 123456000),
    Kind.vec => VectorValue(<double>[1, 2, 3]),
    Kind.ref => null,
    Kind.any => 7,
  };
}

/// A value that is not of [kind], or null for a kind that accepts anything.
Object? _wrong(Kind kind) {
  return switch (kind) {
    Kind.any => null,
    Kind.num || Kind.int || Kind.small => 'x',
    Kind.vec => <Object?>[1, 2, 3],
    Kind.arr || Kind.numArr || Kind.strArr => <String, Object?>{'a': 1},
    _ => 7,
  };
}

/// For every function of [functionCatalog]: calls with valid arguments, and
/// with every one or two of the arguments replaced by null, by a field that
/// does not exist, by a value of the wrong type and by an expression that
/// fails. This pins what wins when several of these meet (an error, a type
/// mismatch, null), which differs between functions.
List<Expression> edgeMatrix() {
  final Expression failing = constant(1).divide(0);
  final List<Expression> result = <Expression>[];
  for (final Fn function in functionCatalog) {
    Expression valid(int i) {
      final List<String>? literals = function.literals?[i];
      if (literals != null) {
        return constant(literals.first);
      }
      return function.args[i] == Kind.ref
          ? field('__name__')
          : constant(_sample(function.args[i]));
    }

    List<Expression> specials(int i) {
      if (function.literals?[i] != null) {
        return const <Expression>[];
      }
      final Object? wrong = _wrong(function.args[i]);
      return <Expression>[
        constant(null),
        field('zz'),
        if (wrong != null) constant(wrong),
        failing,
      ];
    }

    final int count = function.args.length;
    result.add(
      FunctionExpression(function.name, <Expression>[
        for (int i = 0; i < count; i++) valid(i),
      ]),
    );
    for (int p = 0; p < count; p++) {
      for (final Expression special in specials(p)) {
        result.add(
          FunctionExpression(function.name, <Expression>[
            for (int i = 0; i < count; i++) i == p ? special : valid(i),
          ]),
        );
        // Pairs: what wins when two of them meet. Only with the first
        // arguments, to keep the matrix small.
        for (int q = p + 1; q < count && q < 3; q++) {
          for (final Expression other in specials(q)) {
            if (identical(other, special)) {
              continue;
            }
            result.add(
              FunctionExpression(function.name, <Expression>[
                for (int i = 0; i < count; i++)
                  i == p ? special : (i == q ? other : valid(i)),
              ]),
            );
          }
        }
      }
    }
  }
  return result;
}

/// The aggregate functions the local evaluator implements.
const List<String> aggregateFunctions = <String>[
  'count', 'count_if', 'count_distinct', 'sum', 'average', 'minimum', //
  'maximum', 'first', 'last', 'array_agg', 'array_agg_distinct',
];

/// Whether [local] and [remote] hold the same values, in any order (the
/// result of `array_agg_distinct` has no order).
bool sameElements(model.FieldValue local, model.FieldValue remote) {
  if (local is! model.ArrayValue || remote is! model.ArrayValue) {
    return false;
  }
  final List<model.FieldValue> rest = remote.internalValue.toList();
  for (final model.FieldValue element in local.internalValue) {
    final int index = rest.indexWhere(
      (model.FieldValue other) => sameValue(element, other),
    );
    if (index < 0) {
      return false;
    }
    rest.removeAt(index);
  }
  return rest.isEmpty;
}
