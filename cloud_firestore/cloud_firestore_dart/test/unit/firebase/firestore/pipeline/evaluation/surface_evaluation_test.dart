// Local evaluation of the pipeline surface added to match the JS SDK
// (notes/parity/pipelines_surface_diff.md): `sum(array)` (arraySum),
// `map_set` with several pairs, `log10`, and what is deliberately not
// evaluated locally (search and window functions).
//
// Android has no local evaluation for any of these (its registry has
// `map_set` as not implemented and no `sum`, `log10`, `document_matches`,
// `score`; its AddWindowFieldsStage has no `evaluate`), so the expected values
// are the answers of the Enterprise emulator (v1.22.0), also recorded in
// emulator_results.golden.jsonl.

// 64-bit integers and integral doubles: VM only, like evaluator_test.dart.
@TestOn('vm')
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show Decimal128Value, FieldValue, Int32Value;
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:test/test.dart';

import '../../../../../util/property_pipeline.dart';
import '../../../../../util/property_pipeline_stages.dart';
import '../pipeline_test_util.dart';

final LocalEvaluation local = LocalEvaluation(DatabaseId.forProject('project'));
final LocalPipelines pipelines = LocalPipelines(testDatabaseId);

EvaluateResult evaluate(
  Expression expression, [
  Map<String, Object?> data = const <String, Object?>{},
]) => local.evaluate(expression, 'coll/doc', data);

Object? valueOf(Expression expression, [Map<String, Object?>? data]) =>
    evaluate(expression, data ?? const <String, Object?>{}).value?.value;

Matcher unsupported(String text) => throwsA(
  isA<UnsupportedExpression>().having(
    (UnsupportedExpression e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  group('arraySum', () {
    Object? sum(List<Object?> values) => valueOf(constant(values).arraySum());

    test('adds integers to an integer and mixes to a double', () {
      expect(sum(<Object?>[3, 1, 2]), 6);
      expect(
        evaluate(constant(<Object?>[3, 1, 2]).arraySum()).value,
        isA<model.IntegerValue>(),
      );
      expect(sum(<Object?>[1, 2.5]), 3.5);
      expect(sum(<Object?>[1.5, 2.5]), 4.0);
      expect(
        evaluate(constant(<Object?>[1.5, 2.5]).arraySum()).value,
        isA<model.DoubleValue>(),
      );
      expect(sum(<Object?>[0.1, 0.2, 0.3]), 0.1 + 0.2 + 0.3);
    });

    test('skips what is not a number', () {
      expect(sum(<Object?>[3, 'a', null, 1.5]), 4.5);
      expect(sum(<Object?>[1, null, 2]), 3);
      expect(
        sum(<Object?>[
          1,
          true,
          <Object?>[5],
        ]),
        1,
      );
    });

    test('is null without numbers, for null and for a missing value', () {
      for (final List<Object?> values in <List<Object?>>[
        <Object?>[],
        <Object?>[null],
        <Object?>[true],
        <Object?>[
          <Object?>[1, 2],
        ],
      ]) {
        expect(
          evaluate(constant(values).arraySum()).value,
          isA<model.NullValue>(),
          reason: '$values',
        );
      }
      expect(evaluate(constant(null).arraySum()).value, isA<model.NullValue>());
      expect(
        evaluate(field('missing').arraySum()).value,
        isA<model.NullValue>(),
      );
    });

    test('is an error for a value that is not an array', () {
      for (final Object value in <Object>[
        7,
        'abc',
        <String, Object?>{'a': 1},
      ]) {
        expect(
          evaluate(constant(value).arraySum()).isError,
          isTrue,
          reason: '$value',
        );
      }
      expect(
        evaluate(field('v').arraySum(), <String, Object?>{
          'v': FieldValue.vector(<double>[1, 2]),
        }).isError,
        isTrue,
      );
      expect(evaluate(constant(1).divide(0).arraySum()).isError, isTrue);
    });

    test('fails on an int64 overflow of the running total', () {
      expect(
        evaluate(
          constant(<Object?>[9223372036854775807, 1]).arraySum(),
        ).isError,
        isTrue,
      );
      expect(
        evaluate(
          constant(<Object?>[-9223372036854775807 - 1, -1]).arraySum(),
        ).isError,
        isTrue,
      );
      // Order matters: the total overflows before the -2 comes.
      expect(
        evaluate(
          constant(<Object?>[9223372036854775807, 1, -2]).arraySum(),
        ).isError,
        isTrue,
      );
      // With a double the sum is a double.
      expect(sum(<Object?>[9223372036854775807, 1.0]), 9223372036854775808.0);
    });

    test('special doubles', () {
      expect((sum(<Object?>[1, double.nan])! as double).isNaN, isTrue);
      expect(
        (sum(<Object?>[double.infinity, double.negativeInfinity])! as double)
            .isNaN,
        isTrue,
      );
      final double zero = sum(<Object?>[-0.0, -0.0])! as double;
      expect(zero, 0.0);
      expect(zero.isNegative, isFalse);
    });

    test('Int32 adds to an int64 and Decimal128 to a Decimal128', () {
      expect(sum(<Object?>[Int32Value(2147483647), Int32Value(1)]), 2147483648);
      expect(sum(<Object?>[Int32Value(2), 3]), 5);
      expect(
        evaluate(
          constant(<Object?>[Decimal128Value('1.5'), 1]).arraySum(),
        ).value,
        isA<model.Decimal128FieldValue>(),
      );
      expect(
        sum(<Object?>[Decimal128Value('1.5'), 2.5]),
        Decimal128Value('4.0'),
      );
    });

    test('takes exactly one argument', () {
      expect(
        evaluate(
          FunctionExpression('sum', <Object?>[
            <Object?>[1],
            <Object?>[2],
          ]),
        ).isError,
        isTrue,
      );
      expect(evaluate(FunctionExpression('sum')).isError, isTrue);
    });

    test('in a stage, sum is the scalar function; in aggregate the '
        'aggregate', () {
      final Map<String, Map<String, Object?>> docs =
          <String, Map<String, Object?>>{
            'c/a': <String, Object?>{
              'xs': <Object?>[1, 2],
            },
            'c/b': <String, Object?>{
              'xs': <Object?>[3],
            },
          };
      final List<PipelineRow> rows = pipelines.run(
        source()
            .collection('c')
            .sort(<Ordering>[field(Field.documentIdName).ascending()])
            .select(<Selectable>[field('xs').arraySum().as('s')]),
        docs,
      );
      expect(
        rows.map(
          (PipelineRow r) =>
              r.fields.get(FieldPath.fromServerFormat('s'))!.value,
        ),
        <Object?>[3, 3],
      );
      final List<PipelineRow> total = pipelines.run(
        source().collection('c').aggregate(<AliasedAggregate>[
          field('xs').arraySum().sum().as('t'),
        ]),
        docs,
      );
      expect(
        total.single.fields.get(FieldPath.fromServerFormat('t'))!.value,
        6,
      );
    });
  });

  group('mapSet with several pairs', () {
    final Map<String, Object?> doc = <String, Object?>{
      'm': <String, Object?>{'k': 1, 'j': 'x'},
    };
    Object? set(Expression expression) => valueOf(expression, doc);

    test('applies the pairs in order', () {
      expect(
        set(field('m').mapSet('a', 1, <Object?>['b', 2])),
        <String, Object?>{'a': 1, 'b': 2, 'j': 'x', 'k': 1},
      );
      expect(
        set(field('m').mapSet('a', 1, <Object?>['a', 2])),
        <String, Object?>{'a': 2, 'j': 'x', 'k': 1},
      );
      expect(
        set(field('m').mapSet('a', 1, <Object?>['b', 2, 'c', 3])),
        <String, Object?>{'a': 1, 'b': 2, 'c': 3, 'j': 'x', 'k': 1},
      );
    });

    test(
      'a missing value removes the key, also one set by an earlier pair',
      () {
        expect(
          set(field('m').mapSet('k', field('missing'), <Object?>['q', 1])),
          <String, Object?>{'j': 'x', 'q': 1},
        );
        expect(
          set(field('m').mapSet('q', 1, <Object?>['q', field('missing')])),
          <String, Object?>{'j': 'x', 'k': 1},
        );
        expect(
          set(field('m').mapSet('q', 1, <Object?>['q', null])),
          <String, Object?>{'j': 'x', 'k': 1, 'q': null},
        );
      },
    );

    test('anything but a map is missing; an error is an error', () {
      expect(
        evaluate(constant(null).mapSet('a', 1, <Object?>['b', 2])).isUnset,
        isTrue,
      );
      expect(
        evaluate(
          constant(7).mapSet('a', constant(1).divide(0), <Object?>['a', 7]),
        ).isUnset,
        isTrue,
      );
      expect(
        evaluate(
          field('m').mapSet('a', 1, <Object?>['b', constant(1).divide(0)]),
          doc,
        ).isError,
        isTrue,
      );
      expect(
        evaluate(
          constant(1).divide(0).mapSet('a', 1, <Object?>['b', 2]),
        ).isError,
        isTrue,
      );
    });

    test('arguments the emulator rejects are an error', () {
      // The emulator rejects these pipelines before it runs them.
      expect(
        evaluate(
          FunctionExpression('map_set', <Object?>[field('m'), 'a', 1, 'b']),
          doc,
        ).isError,
        isTrue,
      );
      expect(
        evaluate(
          FunctionExpression('map_set', <Object?>[field('m'), 'a']),
          doc,
        ).isError,
        isTrue,
      );
      expect(
        evaluate(field('m').mapSet('a', 1, <Object?>[7, 2]), doc).isError,
        isTrue,
      );
    });
  });

  group('log10', () {
    test('agrees with the emulator', () {
      expect(valueOf(constant(100).log10()), 2.0);
      expect(valueOf(constant(1000.0).log10()), 3.0);
      expect(valueOf(constant(2).log10()), closeTo(0.30103, 1e-5));
      expect((valueOf(constant(double.nan).log10())! as double).isNaN, isTrue);
      expect(valueOf(constant(double.infinity).log10()), double.infinity);
      // Zero, negative numbers and -infinity: an error or NaN, as recorded.
      expect(evaluate(constant(0.0).log10()).isError, isTrue);
      expect(evaluate(constant(-0.0).log10()).isError, isTrue);
      expect(
        (valueOf(constant(double.negativeInfinity).log10())! as double).isNaN,
        isTrue,
      );
      expect(evaluate(constant('x').log10()).isError, isTrue);
      expect(evaluate(constant(null).log10()).value, isA<model.NullValue>());
    });
  });

  group('not evaluated locally', () {
    test('the search functions, with the reason', () {
      expect(ExpressionEvaluator.supports('document_matches'), isFalse);
      expect(ExpressionEvaluator.supports('score'), isFalse);
      expect(
        () => evaluate(documentMatches('waffles')),
        unsupported('full-text search'),
      );
      expect(() => evaluate(score()), unsupported('search stage'));
    });

    test('the search and add_window_fields stages, with the reason', () {
      final Map<String, Map<String, Object?>> docs =
          <String, Map<String, Object?>>{
            'c/a': <String, Object?>{'n': 1},
          };
      expect(
        () => pipelines.run(source().collection('c').search('waffles'), docs),
        unsupported('search index'),
      );
      expect(
        () => pipelines.run(
          source().collection('c').addWindowFields(
            WindowSpec(sort: <Ordering>[field('n').ascending()]),
            <Object>[rank().as('r')],
          ),
          docs,
        ),
        unsupported('add_window_fields'),
      );
      expect(
        () => pipelines.run(
          source().collection('c').addWindowFields(const WindowSpec(), <Object>[
            field('n').sum().as('t'),
          ]),
          docs,
        ),
        unsupported('no SDK evaluates it offline'),
      );
    });
  });
}
