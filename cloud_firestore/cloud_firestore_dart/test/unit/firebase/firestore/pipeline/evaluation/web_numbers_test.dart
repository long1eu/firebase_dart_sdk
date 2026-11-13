// Numbers in local pipeline evaluation on every platform, also compiled to
// JavaScript, where an `int` is a double: integers are exact up to 2^53 there,
// and an expression with an integer operand or result beyond that is not
// evaluated locally (UnsupportedExpression) instead of evaluated wrong.
//
// The expressions are written in wire form, so that a double with an integral
// value stays a double (the literal 2.0 is an int in JavaScript).
//
// Run compiled to JavaScript with
//   tool/test_unit_browser.sh test/unit/firebase/firestore/pipeline/evaluation

import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/aggregate_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/pipeline_executor.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

final ExpressionEvaluator evaluator = ExpressionEvaluator(
  DatabaseId.forProject('project'),
);
final EvaluationInput input = EvaluationInput(ObjectValue.empty);

pb.Value integer(Object value) =>
    pb.Value()
      ..integerValue = value is Int64 ? value : Int64.parseInt('$value');

pb.Value float(double value) => pb.Value()..doubleValue = value;

pb.Value call(String name, List<pb.Value> args) =>
    pb.Value()
      ..functionValue = (pb.Function_()
        ..name = name
        ..args.addAll(args));

pb.Value timestampOf(int seconds) =>
    pb.Value()..timestampValue = (proto.Timestamp()..seconds = Int64(seconds));

EvaluateResult evaluate(pb.Value expression) =>
    evaluator.evaluate(expression, input);

/// The integer result of [expression], with its type checked.
int integerOf(pb.Value expression) {
  final FieldValue? value = evaluate(expression).value;
  expect(value, isA<IntegerValue>());
  return (value! as IntegerValue).value;
}

/// The double result of [expression], with its type checked.
double doubleOf(pb.Value expression) {
  final FieldValue? value = evaluate(expression).value;
  expect(value, isA<DoubleValue>());
  return (value! as DoubleValue).value;
}

final Matcher unsupportedOnTheWeb = throwsA(isA<UnsupportedExpression>());

void main() {
  const int maxSafe = 9007199254740991; // 2^53 - 1

  test('integers and doubles keep their types', () {
    expect(integerOf(call('add', <pb.Value>[integer(2), integer(3)])), 5);
    expect(doubleOf(call('add', <pb.Value>[float(2), integer(3)])), 5);
    expect(integerOf(call('divide', <pb.Value>[integer(7), integer(2)])), 3);
    expect(integerOf(call('divide', <pb.Value>[integer(-7), integer(2)])), -3);
    expect(doubleOf(call('divide', <pb.Value>[float(7), integer(2)])), 3.5);
    expect(integerOf(call('mod', <pb.Value>[integer(-7), integer(2)])), -1);
    expect(doubleOf(call('floor', <pb.Value>[float(2.5)])), 2);
    expect(integerOf(call('abs', <pb.Value>[integer(-4)])), 4);
    expect(
      evaluate(call('divide', <pb.Value>[integer(1), integer(0)])).isError,
      isTrue,
    );
    expect(
      doubleOf(call('divide', <pb.Value>[float(1), integer(0)])),
      double.infinity,
    );
  });

  test('a negative zero stays negative', () {
    expect(doubleOf(call('sqrt', <pb.Value>[float(-0.0)])).isNegative, isTrue);
    expect(
      doubleOf(call('multiply', <pb.Value>[float(-1), integer(0)])).isNegative,
      isTrue,
    );
    expect(
      doubleOf(call('round', <pb.Value>[float(-0.4)])).isNegative,
      isFalse,
    );
  });

  test('equality and order across the number types', () {
    final pb.Value two = integer(2);
    expect(
      evaluate(call('equal', <pb.Value>[two, float(2)])).value,
      BoolValue.valueOf(true),
    );
    expect(
      evaluate(call('less_than', <pb.Value>[two, float(2.5)])).value,
      BoolValue.valueOf(true),
    );
    expect(
      evaluate(call('type', <pb.Value>[float(2)])).value,
      StringValue.valueOf('float64'),
    );
    expect(
      evaluate(call('type', <pb.Value>[two])).value,
      StringValue.valueOf('int64'),
    );
  });

  test('integers up to 2^53 are exact', () {
    expect(
      integerOf(call('add', <pb.Value>[integer(maxSafe - 1), integer(1)])),
      maxSafe,
    );
    expect(
      integerOf(
        call('subtract', <pb.Value>[integer(-maxSafe + 1), integer(1)]),
      ),
      -maxSafe,
    );
    expect(
      integerOf(
        call('multiply', <pb.Value>[integer(94906265), integer(94906265)]),
      ),
      9007199136250225,
    );
    expect(
      integerOf(
        call('timestamp_to_unix_micros', <pb.Value>[timestampOf(1700000000)]),
      ),
      1700000000000000,
    );
  });

  test('beyond 2^53 integers are 64-bit on the VM and not evaluated on the '
      'web', () {
    final pb.Value beyond = call('add', <pb.Value>[
      integer(maxSafe),
      integer(1),
    ]);
    final pb.Value large = integer('1152921504606846977'); // 2^60 + 1
    final pb.Value micros = call('timestamp_to_unix_micros', <pb.Value>[
      timestampOf(253402300799), // 9999-12-31T23:59:59Z
    ]);
    final pb.Value overflow = call('add', <pb.Value>[
      integer('9223372036854775807'),
      integer(1),
    ]);
    if (jsIntegers) {
      expect(() => evaluate(beyond), unsupportedOnTheWeb);
      expect(
        () => evaluate(call('add', <pb.Value>[large, integer(0)])),
        unsupportedOnTheWeb,
      );
      expect(() => evaluate(micros), unsupportedOnTheWeb);
      expect(() => evaluate(overflow), unsupportedOnTheWeb);
    } else {
      expect(integerOf(beyond), maxSafe + 1);
      expect(
        integerOf(call('add', <pb.Value>[large, integer(0)])),
        int.parse('1152921504606846977'),
      );
      expect(integerOf(micros), int.parse('253402300799000000'));
      expect(evaluate(overflow).isError, isTrue);
    }
    // A double result is fine on every platform.
    expect(
      doubleOf(call('add', <pb.Value>[large, float(0)])),
      1152921504606846976.0,
    );
  });

  test('integer sums', () {
    final AggregateEvaluator aggregates = AggregateEvaluator(evaluator);
    EvaluateResult sum(List<int> values) => aggregates.aggregate(
      call('sum', <pb.Value>[pb.Value()..fieldReferenceValue = 'x']),
      <EvaluationInput>[
        for (final int value in values)
          EvaluationInput(
            ObjectValue.fromMap(<String, FieldValue>{
              'x': IntegerValue.valueOf(value),
            }),
          ),
      ],
    );
    expect(sum(<int>[maxSafe - 2, 1, 1]).value, IntegerValue.valueOf(maxSafe));
    if (jsIntegers) {
      expect(() => sum(<int>[maxSafe, 1]), unsupportedOnTheWeb);
    } else {
      expect(sum(<int>[maxSafe, 1]).value, IntegerValue.valueOf(maxSafe + 1));
    }
  });

  test('a pipeline sorts and groups numbers by value', () {
    final PipelineExecutor executor = PipelineExecutor(
      DatabaseId.forProject('project'),
    );
    EvaluationInput document(String id, FieldValue x) => EvaluationInput(
      ObjectValue.fromMap(<String, FieldValue>{
        'x': x,
        'id': StringValue.valueOf(id),
      }),
      key: DocumentKey.fromPathString('c/$id'),
    );
    final List<EvaluationInput> documents = <EvaluationInput>[
      document('a', DoubleValue.valueOf(2)),
      document('b', IntegerValue.valueOf(1)),
      document('c', IntegerValue.valueOf(2)),
      document('d', DoubleValue.valueOf(-0.0)),
      document('e', DoubleValue.valueOf(double.nan)),
    ];
    pb.Pipeline_Stage stage(String name, List<pb.Value> args) =>
        pb.Pipeline_Stage()
          ..name = name
          ..args.addAll(args);
    pb.Value map(Map<String, pb.Value> fields) =>
        pb.Value()..mapValue = (pb.MapValue()..fields.addAll(fields));
    pb.Value fieldOf(String name) => pb.Value()..fieldReferenceValue = name;
    final pb.Value collection = pb.Value()..referenceValue = '/c';

    final List<EvaluationInput> sorted = executor.execute(
      pb.Pipeline()
        ..stages.addAll(<pb.Pipeline_Stage>[
          stage('collection', <pb.Value>[collection]),
          stage('sort', <pb.Value>[
            map(<String, pb.Value>{
              'direction': pb.Value()..stringValue = 'ascending',
              'expression': fieldOf('x'),
            }),
          ]),
        ]),
      documents,
    );
    expect(
      sorted.map((EvaluationInput row) => row.key!.path.last).toList(),
      <String>['e', 'd', 'b', 'a', 'c'],
    );

    final List<EvaluationInput> groups = executor.execute(
      pb.Pipeline()
        ..stages.addAll(<pb.Pipeline_Stage>[
          stage('collection', <pb.Value>[collection]),
          stage('aggregate', <pb.Value>[
            map(<String, pb.Value>{'n': call('count', <pb.Value>[])}),
            map(<String, pb.Value>{'x': fieldOf('x')}),
          ]),
        ]),
      documents,
    );
    expect(
      groups.map(
        (EvaluationInput row) =>
            row.fields.get(FieldPath.fromSingleSegment('n')),
      ),
      <FieldValue>[
        IntegerValue.valueOf(2),
        IntegerValue.valueOf(1),
        IntegerValue.valueOf(1),
        IntegerValue.valueOf(1),
      ],
    );
  });
}
