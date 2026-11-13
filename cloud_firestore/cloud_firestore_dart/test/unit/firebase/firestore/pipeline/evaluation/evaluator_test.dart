// The parts of local pipeline evaluation that the tests ported from Android
// and the recorded emulator results do not reach: what is not supported,
// variables, the clock, aggregates, decimal arithmetic and the translation
// of RE2 patterns.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show Blob, Decimal128Value, Int32Value, Timestamp;
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/aggregate_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/decimal.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/re2.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart'
    show PipelineEncoder;
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:test/test.dart';

import '../../../../../util/property_pipeline.dart';

final DatabaseId databaseId = DatabaseId.forProject('project');
final PipelineEncoder encoder = PipelineEncoder(databaseId);
final LocalEvaluation local = LocalEvaluation(databaseId);

EvaluateResult evaluate(
  Expression expression, [
  Map<String, Object?> data = const <String, Object?>{},
]) => local.evaluate(expression, 'coll/doc', data);

Object? valueOf(EvaluateResult result) => result.value?.value;

void main() {
  group('what is not evaluated locally', () {
    test('an unknown function', () {
      expect(ExpressionEvaluator.supports('geo_distance'), isFalse);
      expect(
        () => evaluate(FunctionExpression('geo_distance', <Object?>[1, 2])),
        throwsA(
          isA<UnsupportedExpression>().having(
            (UnsupportedExpression e) => e.message,
            'message',
            contains('geo_distance'),
          ),
        ),
      );
      // Also when the result would not depend on it: the expression as a
      // whole can not be trusted.
      expect(
        () => evaluate(
          FunctionExpression('or', <Object?>[
            false,
            FunctionExpression('current_document'),
          ]),
        ),
        throwsA(isA<UnsupportedExpression>()),
      );
    });

    test('a subquery', () {
      final pb.Value subquery = pb.Value()..pipelineValue = pb.Pipeline();
      expect(
        () => ExpressionEvaluator(
          databaseId,
        ).evaluate(subquery, EvaluationInput(model.ObjectValue.empty)),
        throwsA(isA<UnsupportedExpression>()),
      );
    });

    test('a variable that is not defined', () {
      expect(
        () => evaluate(variable('x')),
        throwsA(isA<UnsupportedExpression>()),
      );
    });

    test('a time zone other than UTC', () {
      final Expression ts = constant(const Timestamp(1700000000, 0));
      expect(valueOf(evaluate(ts.timestampExtract('hour', 'UTC'))), 22);
      expect(
        () => evaluate(ts.timestampExtract('hour', 'Asia/Tokyo')),
        throwsA(
          isA<UnsupportedExpression>().having(
            (UnsupportedExpression e) => e.message,
            'message',
            contains('Asia/Tokyo'),
          ),
        ),
      );
      expect(
        () => evaluate(ts.timestampTruncate('day', 'America/New_York')),
        throwsA(isA<UnsupportedExpression>()),
      );
    });

    test(
      'every implemented function is in the generator of the property test',
      () {
        final Set<String> generated = <String>{
          for (final Fn function in functionCatalog) function.name,
          'array_filter', 'array_transform', // generated as lambdas
        };
        expect(
          ExpressionEvaluator.supportedFunctions.toSet().difference(generated),
          // No repeatable result, or not comparable through select().
          <String>{'rand', 'current_timestamp', 'map', 'exists', 'is_absent'},
        );
      },
    );
  });

  group('input', () {
    test('variables are passed in and scoped by lambdas', () {
      final ExpressionEvaluator evaluator = ExpressionEvaluator(databaseId);
      final EvaluationInput input = EvaluationInput(
        local.toModel(<String, Object?>{'a': 2}) as model.ObjectValue,
      );
      EvaluateResult run(Expression expression) => evaluator.evaluate(
        expression.toProto(encoder),
        input,
        variables: <String, EvaluateResult>{
          'x': EvaluateValue(model.IntegerValue.valueOf(40)),
          'missing': EvaluateResult.unset,
        },
      );
      expect(valueOf(run(variable('x').add(field('a')))), 42);
      expect(run(variable('missing')).isUnset, isTrue);
      // The element shadows the outer variable inside the lambda only.
      expect(
        valueOf(
          run(
            array(<Object?>[1, 2]).arrayTransform(
              (Expression x) => x.add(variable('x')),
              alias: 'x',
            ),
          ),
        ),
        <Object?>[2, 4],
      );
      expect(valueOf(run(variable('x'))), 40);
    });

    test('the document key and times are fields', () {
      final ExpressionEvaluator evaluator = ExpressionEvaluator(databaseId);
      final EvaluationInput input = EvaluationInput(
        model.ObjectValue.empty,
        key: DocumentKey.fromPathString('coll/doc/sub/item'),
        createTime: const Timestamp(1, 0),
        updateTime: const Timestamp(2, 0),
      );
      EvaluateResult run(Expression expression) =>
          evaluator.evaluate(expression.toProto(encoder), input);
      expect(valueOf(run(field('__name__').documentId())), 'item');
      expect(valueOf(run(field('__name__').collectionId())), 'sub');
      expect(valueOf(run(field('__name__').parent().documentId())), 'doc');
      expect(valueOf(run(field('__create_time__'))), const Timestamp(1, 0));
      expect(valueOf(run(field('__update_time__'))), const Timestamp(2, 0));
      // An intermediate result of a pipeline has none of them.
      final EvaluationInput row = EvaluationInput(model.ObjectValue.empty);
      expect(
        evaluator.evaluate(field('__name__').toProto(encoder), row).isUnset,
        isTrue,
      );
      expect(
        evaluator
            .evaluate(field('__update_time__').toProto(encoder), row)
            .isUnset,
        isTrue,
      );
    });

    test('the clock and the random source can be replaced', () {
      final ExpressionEvaluator evaluator = ExpressionEvaluator(
        databaseId,
        now: () => const Timestamp(1234, 5000),
      );
      final EvaluationInput input = EvaluationInput(model.ObjectValue.empty);
      expect(
        valueOf(
          evaluator.evaluate(
            FunctionExpression('current_timestamp').toProto(encoder),
            input,
          ),
        ),
        const Timestamp(1234, 5000),
      );
      final Object? random = valueOf(
        evaluator.evaluate(FunctionExpression('rand').toProto(encoder), input),
      );
      expect(random, isA<double>());
      expect(random! as double, inInclusiveRange(0, 1));
    });
  });

  group('aggregates', () {
    // The results of the Enterprise edition emulator for these inputs.
    Object? aggregate(
      String name,
      List<Object?> values, {
      Expression? argument,
    }) {
      final Map<String, Map<String, Object?>> documents =
          <String, Map<String, Object?>>{
            for (int i = 0; i < values.length; i++)
              'coll/d$i': identical(values[i], #missing)
                  ? <String, Object?>{}
                  : <String, Object?>{'x': values[i]},
          };
      final EvaluateResult result = local.aggregate(
        AggregateFunction(name, <Object?>[argument ?? field('x')]),
        documents,
      );
      return result.isError ? #error : result.value!.value;
    }

    test('of nothing', () {
      for (final String name in <String>[
        'count',
        'count_if',
        'count_distinct',
      ]) {
        expect(aggregate(name, <Object?>[]), 0, reason: name);
      }
      for (final String name in <String>[
        'sum', 'average', 'minimum', 'maximum', 'first', 'last', //
      ]) {
        expect(aggregate(name, <Object?>[]), isNull, reason: name);
      }
      expect(aggregate('array_agg', <Object?>[]), isEmpty);
      expect(aggregate('array_agg_distinct', <Object?>[]), isEmpty);
    });

    test(
      'count() counts the inputs, count(x) the values that are not null',
      () {
        final List<Object?> values = <Object?>[null, 2, #missing, null];
        expect(
          local
              .aggregate(
                AggregateFunction('count'),
                <String, Map<String, Object?>>{
                  for (int i = 0; i < 4; i++) 'coll/d$i': <String, Object?>{},
                },
              )
              .value!
              .value,
          4,
        );
        expect(aggregate('count', values), 1);
        expect(aggregate('count_distinct', values), 1);
        expect(
          aggregate('count_distinct', <Object?>[3, 1.5, 3.0, Int32Value(2)]),
          3,
        );
        expect(
          aggregate('count_if', <Object?>[
            3,
            1,
            null,
            'a',
          ], argument: field('x').greaterThan(1)),
          1,
        );
      },
    );

    test('sum and average ignore what is not a number', () {
      expect(aggregate('sum', <Object?>[3, 1, 3, 2]), 9);
      expect(aggregate('average', <Object?>[3, 1, 3, 2]), 2.25);
      expect(aggregate('sum', <Object?>[3, 1.5, 3.0, Int32Value(2)]), 9.5);
      expect(aggregate('sum', <Object?>[Int32Value(2), Int32Value(3)]), 5);
      expect(aggregate('sum', <Object?>['b', 2, 'a', true]), 2);
      expect(aggregate('average', <Object?>['b', 2, 'a', true]), 2.0);
      expect(aggregate('sum', <Object?>[null, #missing]), isNull);
      expect(
        aggregate('average', <Object?>[
          <Object?>[1],
        ]),
        isNull,
      );
      expect(aggregate('sum', <Object?>[double.nan, 2]), isNaN);
      expect(
        aggregate('sum', <Object?>[double.infinity, double.negativeInfinity]),
        isNaN,
      );
      final Object? decimal = aggregate('sum', <Object?>[
        1,
        Decimal128Value('1.5'),
      ]);
      expect((decimal! as Decimal128Value).stringValue, '2.5');
      final Object? mean = aggregate('average', <Object?>[
        1,
        Decimal128Value('1.5'),
      ]);
      expect((mean! as Decimal128Value).stringValue, '1.25');
    });

    test('an integer sum that overflows is an error', () {
      expect(aggregate('sum', <Object?>[9223372036854775807, 1]), #error);
      expect(aggregate('average', <Object?>[9223372036854775807, 1]), #error);
      expect(
        aggregate('sum', <Object?>[9223372036854775807, 1.0]),
        9223372036854775807 + 1.0,
      );
    });

    test('minimum and maximum order all types and skip null', () {
      expect(aggregate('minimum', <Object?>['b', 2, 'a', true]), true);
      expect(aggregate('maximum', <Object?>['b', 2, 'a', true]), 'b');
      expect(aggregate('minimum', <Object?>[null, 2, #missing]), 2);
      expect(aggregate('minimum', <Object?>[double.nan, 2]), isNaN);
      expect(aggregate('maximum', <Object?>[double.nan, 2]), 2);
      // Of equal values the first one.
      expect(aggregate('maximum', <Object?>[3, 1.5, 3.0]), isA<int>());
    });

    test('first, last and array_agg follow the order of the inputs', () {
      expect(aggregate('first', <Object?>[3, 1, 2]), 3);
      expect(aggregate('last', <Object?>[3, 1, 2]), 2);
      expect(aggregate('first', <Object?>[null, 2]), isNull);
      expect(
        aggregate('array_agg', <Object?>[null, 2, #missing, null]),
        <Object?>[null, 2, null],
      );
      expect(
        aggregate('array_agg_distinct', <Object?>[3, 1, 3.0, null, null]),
        unorderedEquals(<Object?>[3.0, 1, null]),
      );
    });

    test('an error in the expression fails the aggregate, except after the '
        'input first() stops at', () {
      final Expression failing = field('x').add(1);
      expect(aggregate('sum', <Object?>[1, 'a'], argument: failing), #error);
      expect(aggregate('last', <Object?>['a', 1], argument: failing), #error);
      expect(aggregate('first', <Object?>[1, 'a'], argument: failing), 2);
      expect(aggregate('first', <Object?>['a', 1], argument: failing), #error);
    });

    test('unknown aggregate functions are not supported', () {
      expect(AggregateEvaluator.supports('sum'), isTrue);
      expect(AggregateEvaluator.supports('median'), isFalse);
      expect(
        () => local.aggregate(
          AggregateFunction('median', <Object?>[field('x')]),
          <String, Map<String, Object?>>{},
        ),
        throwsA(isA<UnsupportedExpression>()),
      );
    });
  });

  test('round(decimal128, places) rounds values between -1 and 1', () {
    // The Enterprise edition emulator fails the whole pipeline with INTERNAL
    // for these (it rounds 1.2345 to 2 places as 1.23), so there is no
    // recorded result to compare with.
    String round(String value, int places) =>
        (valueOf(evaluate(constant(Decimal128Value(value)).round(places)))!
                as Decimal128Value)
            .stringValue;
    expect(Decimal.parse(round('0.1', 2)).compareTo(Decimal.parse('0.1')), 0);
    expect(Decimal.parse(round('0.15', 1)).compareTo(Decimal.parse('0.2')), 0);
    expect(Decimal.parse(round('-0.999', 2)).compareTo(Decimal.parse('-1')), 0);
    expect(Decimal.parse(round('0.5', 0)).compareTo(Decimal.parse('1')), 0);
    expect(
      Decimal.parse(round('1.2345', 2)).compareTo(Decimal.parse('1.23')),
      0,
    );
  });

  test('string_repeat gives at most 1 MiB', () {
    // The results of the Enterprise edition emulator.
    Object? repeat(Object value, int count) {
      final EvaluateResult result = evaluate(
        constant(value).stringRepeat(count),
      );
      return result.isError ? #error : valueOf(result);
    }

    expect(repeat('', 8352455884737516622), '');
    expect(repeat('a', 0), '');
    expect(repeat('a', -1), #error);
    expect((repeat('a', 1048576)! as String).length, 1048576);
    expect(repeat('a', 1048577), #error);
    expect((repeat('é', 524288)! as String).length, 524288);
    expect(repeat('é', 524289), #error);
    expect((repeat('😀', 262144)! as String).runes.length, 262144);
    expect(repeat('😀', 262145), #error);
    expect(repeat('ab', 4611686018427387904), #error);
    expect(repeat(Blob(Uint8List(1)), 1048577), #error);
  });

  group('Decimal', () {
    Decimal d(String text) => Decimal.parse(text);

    test('parses and prints like a decimal128 string', () {
      for (final String text in <String>[
        '0', '-0', '1', '-1', '1.5', '0.1', '100.25', '1E+3', '1.2E+40', //
        '1E-7', '0.000001', 'NaN', 'Infinity', '-Infinity',
      ]) {
        expect(d(text).toString(), text);
      }
      expect(d('1e3').toString(), '1E+3');
      expect(d('+2.50').toString(), '2.50');
      expect(() => d('abc'), throwsFormatException);
      expect(() => d(''), throwsFormatException);
    });

    test('adds, subtracts and multiplies exactly', () {
      expect((d('1.5') + d('1.5')).toString(), '3.0');
      expect((d('0.1') + d('0.2')).toString(), '0.3');
      expect((d('1') - d('1.00')).toString(), '0.00');
      expect((d('1.5') * d('2')).toString(), '3.0');
      expect((d('-1.5') * d('1.5')).toString(), '-2.25');
      expect((d('Infinity') - d('Infinity')).isNaN, isTrue);
      expect((d('Infinity') * d('0')).isNaN, isTrue);
      expect((d('NaN') + d('1')).isNaN, isTrue);
    });

    test('rounds to 34 digits, half to even', () {
      expect(
        (d('1') / d('3')).toString(),
        '0.3333333333333333333333333333333333',
      );
      expect(
        (d('2') / d('3')).toString(),
        '0.6666666666666666666666666666666667',
      );
      expect((d('1.5') / d('3')).toString(), '0.5');
      expect((d('1') / d('0')).toString(), 'Infinity');
      expect((d('-1') / d('0')).toString(), '-Infinity');
      expect((d('0') / d('0')).isNaN, isTrue);
      expect(
        d('12345678901234567890123456789012345').toString(),
        '1.234567890123456789012345678901234E+34',
      );
      expect(
        d('12345678901234567890123456789012355').toString(),
        '1.234567890123456789012345678901236E+34',
      );
    });

    test('converts a double to its exact value', () {
      expect(Decimal.fromDouble(0.5).compareTo(d('0.5')), 0);
      expect(Decimal.fromDouble(2).compareTo(d('2')), 0);
      expect(
        Decimal.fromDouble(0.1).toString(),
        '0.1000000000000000055511151231257827',
      );
      expect(
        Decimal.fromDouble(-434.119).toString(),
        '-434.1190000000000281943357549607754',
      );
      expect(Decimal.fromDouble(double.nan).isNaN, isTrue);
      expect(
        Decimal.fromDouble(double.negativeInfinity).toString(),
        '-Infinity',
      );
    });

    test('remainder, square root, rounding and order', () {
      expect(d('7.5').remainder(d('2')).toString(), '1.5');
      expect(d('-7.5').remainder(d('2')).toString(), '-1.5');
      expect(d('1').remainder(d('0')).isNaN, isTrue);
      expect(d('4').sqrt().toString(), '2');
      expect(d('1.5').sqrt().toString(), '1.224744871391589049098642037352946');
      expect(d('-1').sqrt().isNaN, isTrue);
      expect(d('2.5').roundTo(0, DecimalRounding.halfUp).toString(), '3');
      expect(d('-2.5').roundTo(0, DecimalRounding.halfUp).toString(), '-3');
      expect(d('1.25').roundTo(1, DecimalRounding.halfUp).toString(), '1.3');
      expect(d('1.5').roundTo(0, DecimalRounding.ceiling).toString(), '2');
      expect(d('-1.5').roundTo(0, DecimalRounding.ceiling).toString(), '-1');
      expect(d('-1.5').roundTo(0, DecimalRounding.floor).toString(), '-2');
      expect(d('1.99').roundTo(1, DecimalRounding.down).toString(), '1.9');
      expect(
        d('1234').roundTo(-2, DecimalRounding.halfUp).compareTo(d('1200')),
        0,
      );
      expect(d('1.50').compareTo(d('1.5')), 0);
      expect(d('NaN').compareTo(d('-Infinity')), lessThan(0));
      expect(d('NaN').compareTo(d('NaN')), 0);
      expect(d('-0').compareTo(d('0')), 0);
      expect(d('1E+3').toDouble(), 1000.0);
      expect(d('1.0').isInteger, isTrue);
      expect(d('1.5').isInteger, isFalse);
    });
  });

  group('RE2 patterns', () {
    bool matches(String pattern, String input) =>
        compileRe2(pattern).hasMatch(input);

    test('what RE2 rejects is an invalid pattern', () {
      for (final String pattern in <String>[
        r'(abc)\1', 'a(?=b)', 'a(?!b)', '(?<=a)b', '(?<!a)b', 'a++', 'a*+', //
        '(?>a)', '(', '[a', r'a\', r'\k<x>', r'\y', 'a**',
      ]) {
        expect(
          () => compileRe2(pattern),
          throwsA(isA<InvalidPattern>()),
          reason: pattern,
        );
      }
    });

    test('flags are understood at the start only', () {
      expect(matches('(?i)good', 'Good'), isTrue);
      expect(matches('good', 'Good'), isFalse);
      expect(matches('(?s)a.b', 'a\nb'), isTrue);
      expect(matches('(?m)^b', 'a\nb'), isTrue);
      expect(matches('(?is)A.B', 'a\nb'), isTrue);
      expect(matches('(?i)(?s)A.B', 'a\nb'), isTrue);
      expect(matches('(?i-s)A.B', 'a\nb'), isFalse);
      for (final String pattern in <String>['a(?i)b', '(?i:a)b', '(?U)a+']) {
        expect(
          () => compileRe2(pattern),
          throwsA(isA<UnsupportedPattern>()),
          reason: pattern,
        );
      }
    });

    test('a dot matches everything but a line feed', () {
      expect(matches('a.b', 'a\nb'), isFalse);
      expect(matches('a.b', 'a\rb'), isTrue);
      expect(matches('a.b', 'a b'), isTrue);
      expect(matches('^.\$', '😀'), isTrue);
    });

    test('the syntax Dart does not have is translated', () {
      expect(compileRe2('(?P<x>b)').firstMatch('abc')!.namedGroup('x'), 'b');
      expect(matches(r'\pL', 'é'), isTrue);
      expect(matches(r'\pL', '1'), isFalse);
      expect(matches(r'^\p{Lu}+$', 'ÉA'), isTrue);
      expect(matches(r'\PL', 'é'), isFalse);
      expect(matches('[[:digit:]]', 'a1'), isTrue);
      expect(matches('[[:alpha:][:digit:]]+', '_'), isFalse);
      expect(() => compileRe2('[[:nope:]]'), throwsA(isA<InvalidPattern>()));
      expect(matches(r'\Qa.b\E', 'a.b'), isTrue);
      expect(matches(r'\Qa.b\E', 'axb'), isFalse);
      expect(matches(r'b\z', 'ab'), isTrue);
      expect(matches(r'\Aa', 'ba'), isFalse);
      expect(matches(r'a\-b', 'a-b'), isTrue);
      expect(matches(r'a\_b', 'a_b'), isTrue);
      expect(matches(r'[a\-z]', '-'), isTrue);
      expect(matches('[]]', ']'), isTrue);
      expect(matches('[^]a]', ']'), isFalse);
      expect(matches('a{,2}', 'a{,2}'), isTrue);
      expect(matches('a{2}', 'aa'), isTrue);
      expect(matches('a{2,}?', 'aa'), isTrue);
      expect(matches('}', '}'), isTrue);
    });

    test('character classes are about ASCII', () {
      expect(matches(r'\w', 'é'), isFalse);
      expect(matches(r'\d', '٣'), isFalse);
      expect(matches(r'\w+', 'a_1'), isTrue);
    });

    test('an anchored pattern has to match the whole string', () {
      expect(compileRe2('llo', anchored: true).hasMatch('hello'), isFalse);
      expect(compileRe2('h.*o', anchored: true).hasMatch('hello'), isTrue);
      expect(compileRe2('a|ab', anchored: true).hasMatch('ab'), isTrue);
      expect(compileRe2('(?m)^b', anchored: true).hasMatch('a\nb'), isFalse);
    });
  });
}
