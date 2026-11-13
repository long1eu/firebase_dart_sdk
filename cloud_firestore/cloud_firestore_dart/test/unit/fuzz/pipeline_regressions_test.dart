// Regression tests for the crashes found by pipeline_fuzz_test.dart.

import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_result.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import '../../util/property_model.dart';

pb.Value call(String name, [List<pb.Value> args = const <pb.Value>[]]) =>
    pb.Value()
      ..functionValue = (pb.Function_()
        ..name = name
        ..args.addAll(args));

pb.Value text(String value) => pb.Value()..stringValue = value;

void main() {
  group('a function called with too few arguments evaluates to an error', () {
    final ExpressionEvaluator evaluator = ExpressionEvaluator(modelDatabaseId);
    final EvaluationInput input = EvaluationInput(ObjectValue.empty);

    // Each of these read an argument past the end of the call: a RangeError
    // escaped from the evaluator.
    for (final pb.Value expression in <pb.Value>[
      call('is_error'),
      call('array', <pb.Value>[call('is_error')]),
    ]) {
      test('${expression.functionValue.name}'
          '(${expression.functionValue.args.length} arguments)', () {
        final EvaluateResult result;
        try {
          result = evaluator.evaluate(expression, input);
        } on UnsupportedExpression {
          return;
        }
        expect(result.isError, isTrue, reason: '$result');
      });
    }
  });

  group('PipelineExplainStats', () {
    const String stringValue =
        'type.googleapis.com/google.protobuf.StringValue';

    test('the text of malformed bytes is null, not a parse error', () {
      for (final List<int> bytes in <List<int>>[
        <int>[10, 4],
        <int>[50, 172, 162, 156, 190, 94],
        <int>[10, 217, 212, 141, 179, 13],
        <int>[0],
      ]) {
        final PipelineExplainStats stats = PipelineExplainStats(
          stringValue,
          bytes,
        );
        expect(stats.text, isNull, reason: '$bytes');
        expect(stats.toString(), contains(stringValue));
      }
    });

    test('the text of a valid string is read', () {
      expect(
        PipelineExplainStats(
          stringValue,
          (proto.StringValue()..value = 'plan').writeToBuffer(),
        ).text,
        'plan',
      );
    });
  });
}
