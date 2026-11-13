// The bounds the local evaluator needs before it can be wired to the client
// (pipelines_design.md 8.9 D, security review S10/S11): it runs expressions
// the app chooses over documents that other users can write, so no input may
// make it take unbounded time or memory. One timing test per item, with a
// generous bound (the work takes milliseconds), plus the behaviour around
// each bound.

// 64-bit integers and long inputs: VM only.
@TestOn('vm')
library;

import 'dart:math' as math;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show Decimal128Value;
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/aggregate_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/decimal.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/re2.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart'
    show PipelineEncoder;
import 'package:test/test.dart';

import '../../../../../util/property_pipeline.dart';
import '../../../../../util/property_pipeline_stages.dart';
import '../pipeline_test_util.dart';

final DatabaseId databaseId = DatabaseId.forProject('project');
final LocalEvaluation local = LocalEvaluation(databaseId);

EvaluateResult evaluate(
  Expression expression, [
  Map<String, Object?> data = const <String, Object?>{},
]) => local.evaluate(expression, 'coll/doc', data);

Object? valueOf(Expression expression, [Map<String, Object?>? data]) =>
    evaluate(expression, data ?? const <String, Object?>{}).value?.value;

/// Runs [body] and checks it took less than [seconds].
T timed<T>(T Function() body, {int seconds = 5}) {
  final Stopwatch watch = Stopwatch()..start();
  final T result = body();
  expect(watch.elapsed, lessThan(Duration(seconds: seconds)));
  return result;
}

Matcher unsupported(String text) => throwsA(
  isA<UnsupportedExpression>().having(
    (UnsupportedExpression e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  group('regular expressions match in linear time', () {
    test('patterns that backtrack exponentially', () {
      // Before: (a+)+b took 5.5 s on 24 characters and doubled per character.
      final String input = '${'a' * 20000}c';
      timed(() {
        for (final String pattern in <String>[
          r'(a+)+b',
          r'(a|aa)+b',
          r'(a*)*b',
          r'(?:a|a)*b',
          r'^(a+)+$',
          r'(.*a){20}b',
        ]) {
          expect(
            valueOf(constant(input).regexContains(pattern)),
            isFalse,
            reason: pattern,
          );
          expect(
            valueOf(constant(input).regexMatch(pattern)),
            isFalse,
            reason: pattern,
          );
        }
        expect(valueOf(constant(input).regexFindAll(r'(a+)+')), <Object?>[
          'a' * 20000,
        ]);
      });
    });

    test('a pattern too large to match locally is not evaluated locally', () {
      // RE2 caps a counted repetition at 1000.
      expect(() => compileRe2('a{1001}'), throwsA(isA<InvalidPattern>()));
      expect(compileRe2('a{1000}').hasMatch('a' * 1000), isTrue);
      timed(() {
        expect(
          () => evaluate(constant('x').regexContains('(?:a{1000}){30}')),
          unsupported('too large'),
        );
      });
    });

    test('a match too costly for the step budget is not evaluated locally', () {
      // A program of thousands of instructions over a long input: linear,
      // but beyond the budget the expression goes to the backend. The budget
      // (maxRe2Steps, 5e7 steps) takes a few seconds on a loaded machine, so
      // the bound is generous; the input is long enough that matching it
      // without the budget (about 1,800 instructions x 2e6 positions, 70
      // times the budget) would take minutes and still fail the bound.
      timed(seconds: 30, () {
        expect(
          () => evaluate(
            constant('a' * 2000000).regexContains('(?:a?){900}(?:a){900}b'),
          ),
          unsupported('too long'),
        );
      });
    });

    test('leftmost-first matches and submatches as a backtracking engine', () {
      String? find(String pattern, String input, [int group = 0]) =>
          compileRe2(pattern).firstMatch(input)?.group(group);
      expect(find('a|ab', 'ab'), 'a');
      expect(find('ab|a', 'ab'), 'ab');
      expect(find('a+?', 'aaa'), 'a');
      expect(find('a*?b', 'aab'), 'aab');
      expect(find('(a|b)+', 'abab', 1), 'b');
      expect(find('(a*)*', 'b'), '');
      expect(find('x*', 'ab'), '');
      expect(find(r'(\d+)-(\d+)', 'tel 12-345', 2), '345');
      expect(find('a{2,3}', 'aaaa'), 'aaa');
      expect(find('a{2,3}?', 'aaaa'), 'aa');
      expect(find('(?i)straße', 'STRASSE'), isNull);
      expect(find('(?i)k', 'K'), 'K'); // the Kelvin sign
      expect(find('(?i)[a-z]+', 'ÀBc'), 'Bc');
      expect(find(']', 'a]'), ']');
      expect(find(r'\bfoo\b', 'a foo b'), 'foo');
      expect(find('(?m)^b\$', 'a\nb\nc'), 'b');
      expect(find('^b', 'a\nb'), isNull);
      expect(find('😀+', 'a😀😀'), '😀😀');
      expect(find(r'[\x{1F600}-\x{1F64F}]', 'a😃'), '😃');
      expect(find(r'\p{Lu}\p{Ll}', 'aÉé'), 'Éé');
      expect(
        compileRe2(
          '(?P<year>\\d{4})',
        ).firstMatch('in 2024')!.namedGroup('year'),
        '2024',
      );
    });
  });

  group('like matches without a regular expression', () {
    bool like(String value, String pattern) =>
        valueOf(constant(value).like(pattern))! as bool;

    test('many % against a long value', () {
      // Before: O(n^k) for k % (a RegExp of [^\n]* per %).
      final String value = 'a' * 200000;
      timed(() {
        expect(like(value, '%a%a%a%a%a%a%a%a%b'), isFalse);
        expect(like(value, '%a%a%a%a%a%a%a%a%'), isTrue);
        expect(like(value, '%_a_%_a_%_a_%_b'), isFalse);
        expect(like('$value\n', '%a%a%a%a%a%\n%'), isTrue);
      });
    });

    test('the semantics of % and _', () {
      expect(like('abc', 'abc'), isTrue);
      expect(like('abc', 'a_c'), isTrue);
      expect(like('abc', 'a%'), isTrue);
      expect(like('abc', '%c'), isTrue);
      expect(like('abc', '%b%'), isTrue);
      expect(like('abc', '%d%'), isFalse);
      expect(like('abc', 'ab'), isFalse);
      expect(like('abc', '_'), isFalse);
      expect(like('', '%'), isTrue);
      expect(like('', '_'), isFalse);
      expect(like('aXbXc', 'a%b%c'), isTrue);
      expect(like('abab', '%ab'), isTrue);
      expect(like('aab', 'a%ab'), isTrue);
      expect(like('ab', 'a%%b'), isTrue);
      expect(like('a', 'a%a'), isFalse);
      // Neither % nor _ matches a line feed; a literal one does.
      expect(like('a\nb', 'a%b'), isFalse);
      expect(like('a\nb', 'a_b'), isFalse);
      expect(like('a\nb', 'a\n%'), isTrue);
      expect(like('a\nb\nc', '%\n%\nc'), isTrue);
      expect(like('a\nb', '%'), isFalse);
      // Escapes and code points.
      expect(like('50%', r'50\%'), isTrue);
      expect(like('50x', r'50\%'), isFalse);
      expect(like('a_b', r'a\_b'), isTrue);
      expect(like('😀', '_'), isTrue);
      expect(evaluate(constant('a').like(r'a\')).isError, isTrue);
    });
  });

  group('decimal arithmetic does not scale by huge exponents', () {
    test('operands far apart', () {
      // Before: 1e1000000 + 1 took 83 s, 1e10000000 + 1 did not finish.
      timed(() {
        expect(
          (Decimal.parse('1e1000000') + Decimal.fromInt(1)).toString(),
          '1.000000000000000000000000000000000E+1000000',
        );
        expect(
          (Decimal.parse('1e100000000') + Decimal.fromInt(1)).toString(),
          '1.000000000000000000000000000000000E+100000000',
        );
        expect(
          (Decimal.parse('1e100000000') - Decimal.fromInt(1)).toString(),
          '1.000000000000000000000000000000000E+100000000',
        );
        expect(
          Decimal.parse('1e-100000000').compareTo(Decimal.parse('1e100000000')),
          -1,
        );
        expect(
          Decimal.parse(
            '-1e100000000',
          ).compareTo(Decimal.parse('1e-100000000')),
          -1,
        );
        expect(
          Decimal.parse('1e100000000').remainder(Decimal.fromInt(7)).toString(),
          // 10^100000000 mod 7: 10^6 = 1 (mod 7), 100000000 = 4 (mod 6).
          '4',
        );
        expect(Decimal.parse('1e-100000000').isInteger, isFalse);
        expect(Decimal.parse('0e-100000000').isInteger, isTrue);
        expect(
          valueOf(constant(Decimal128Value('1e1000000')).add(constant(1))),
          Decimal128Value('1E+1000000'),
        );
      });
    });

    test('the shortcuts give the exact result rounded to 34 digits', () {
      final math.Random random = math.Random(42);
      BigInt coefficient() {
        final int digits = 1 + random.nextInt(34);
        BigInt value = BigInt.zero;
        for (int i = 0; i < digits; i++) {
          value = value * BigInt.from(10) + BigInt.from(random.nextInt(10));
        }
        return value;
      }

      for (int n = 0; n < 2000; n++) {
        final Decimal a = Decimal.finite(
          coefficient(),
          random.nextInt(400) - 200,
          negative: random.nextBool(),
        );
        final int gap = 73 + random.nextInt(60);
        final Decimal b = Decimal.finite(
          coefficient(),
          a.exponent - gap,
          negative: random.nextBool(),
        );
        // The exact sum, aligned by hand.
        final BigInt aligned =
            (a.negative ? -a.coefficient : a.coefficient) *
                BigInt.from(10).pow(gap) +
            (b.negative ? -b.coefficient : b.coefficient);
        final Decimal exact = aligned == BigInt.zero
            ? Decimal.finite(
                BigInt.zero,
                b.exponent,
                negative: a.negative && b.negative,
              )
            : Decimal.finite(aligned, b.exponent);
        for (final (Decimal x, Decimal y) in <(Decimal, Decimal)>[
          (a, b),
          (b, a),
        ]) {
          final Decimal sum = x + y;
          expect(sum.coefficient, exact.coefficient, reason: '$x + $y');
          expect(sum.exponent, exact.exponent, reason: '$x + $y');
          expect(sum.negative, exact.negative, reason: '$x + $y');
        }
        final int byValue =
            ((a.negative ? -a.coefficient : a.coefficient) *
                        BigInt.from(10).pow(gap) -
                    (b.negative ? -b.coefficient : b.coefficient))
                .sign;
        expect(a.compareTo(b).sign, byValue, reason: 'compare $a, $b');
        expect(b.compareTo(a).sign, -byValue, reason: 'compare $b, $a');
        if (b.coefficient != BigInt.zero) {
          final BigInt rem = (a.coefficient * BigInt.from(10).pow(gap))
              .remainder(b.coefficient);
          final Decimal expected = rem == BigInt.zero
              ? Decimal.finite(BigInt.zero, b.exponent, negative: a.negative)
              : Decimal.finite(rem, b.exponent, negative: a.negative);
          final Decimal actual = a.remainder(b);
          expect(actual.toString(), expected.toString(), reason: '$a % $b');
        }
      }
    });

    test('zeros far apart keep the exponent rules', () {
      final Decimal big = Decimal.parse('1e200');
      final Decimal zero = Decimal.parse('0e-200');
      // The ideal exponent of the sum is the smaller one, as far as the
      // precision allows.
      expect(
        (big + zero).toString(),
        '1.000000000000000000000000000000000E+200',
      );
      expect(
        (Decimal.parse('0e200') + Decimal.parse('5e-200')).toString(),
        '5E-200',
      );
      expect(
        (Decimal.parse('0e200') + Decimal.parse('-0e-200')).exponent,
        -200,
      );
    });
  });

  group('values built locally are bounded', () {
    test('doubling stage by stage stops at the bound', () {
      // One expression can not double a value per level (its wire form would
      // double too), but every stage can: k stages of x = concat(x, x) build
      // 2^k times the input. 40 stages would be a terabyte.
      final LocalPipelines pipelines = LocalPipelines(testDatabaseId);
      final Map<String, Map<String, Object?>> docs =
          <String, Map<String, Object?>>{
            'c/d': <String, Object?>{
              's': 'x' * 1000,
              'a': List<int>.filled(1000, 1),
            },
          };
      Pipeline doubled(Expression Function(Field x) twice, String name) {
        Pipeline pipeline = source().collection('c');
        for (int i = 0; i < 40; i++) {
          pipeline = pipeline.addFields(<Selectable>[
            twice(field(name)).as(name),
          ]);
        }
        return pipeline;
      }

      timed(() {
        expect(
          () => pipelines.run(
            doubled((Field x) => x.stringConcat(<Object?>[x]), 's'),
            docs,
          ),
          unsupported('string_concat'),
        );
        expect(
          () => pipelines.run(
            doubled((Field x) => x.arrayConcat(<Object?>[x]), 'a'),
            docs,
          ),
          unsupported('array_concat'),
        );
        expect(
          () => pipelines.run(
            doubled((Field x) => x.concat(<Object?>[x]), 's'),
            docs,
          ),
          unsupported('concat'),
        );
      });
      // Below the bound the values are built.
      final Map<String, Object?> data = <String, Object?>{'s': 'x' * 1000};
      expect(
        valueOf(
          field('s').stringConcat(<Object?>[field('s')]).charLength(),
          data,
        ),
        2000,
      );
    });

    test('join, replacements and map_merge', () {
      final Map<String, Object?> data = <String, Object?>{
        's': 'a' * 100000,
        'many': List<String>.filled(100000, ''),
      };
      timed(() {
        expect(
          () => evaluate(field('many').join(field('s')), data),
          unsupported('join'),
        );
        expect(
          () => evaluate(field('s').stringReplaceAll('a', field('s')), data),
          unsupported('string_replace_all'),
        );
        expect(
          valueOf(
            field('s').stringReplaceOne('a', field('s')).charLength(),
            data,
          ),
          199999,
        );
      });
      final Map<String, Object?> big = <String, Object?>{
        for (int i = 0; i < 1000; i++) 'k$i': i,
      };
      expect(
        valueOf(constant(big).mapMerge(<String, Object?>{'z': 1}).length()),
        1001,
      );
    });

    test('array_agg stops at the bound, count_distinct is not quadratic', () {
      final AggregateEvaluator aggregates = AggregateEvaluator(
        ExpressionEvaluator(databaseId),
      );
      final PipelineEncoder encoder = PipelineEncoder(databaseId);
      final EvaluationInput input = EvaluationInput(
        local.toModel(<String, Object?>{'x': 1}) as model.ObjectValue,
      );
      timed(seconds: 30, () {
        expect(
          () => aggregates.aggregate(
            field('x').arrayAgg().toProto(encoder),
            Iterable<EvaluationInput>.generate(
              maxLocalValueSize + 1,
              (_) => input,
            ),
          ),
          unsupported('array_agg'),
        );
      });
      // Before: a linear search per input.
      final List<EvaluationInput> distinct = <EvaluationInput>[
        for (int i = 0; i < 100000; i++)
          EvaluationInput(
            local.toModel(<String, Object?>{'x': i % 50000})
                as model.ObjectValue,
          ),
      ];
      timed(() {
        expect(
          aggregates
              .aggregate(field('x').countDistinct().toProto(encoder), distinct)
              .value
              ?.value,
          50000,
        );
      });
    });
  });
}
