// Replays the recorded results of the Enterprise edition emulator (see
// test/util/pipeline_evaluation_cases.dart) against the local evaluator: the
// same expressions, the same document, without an emulator.
//
// The file is rewritten by
//
//   UPDATE_GOLDEN=1 FIRESTORE_ENTERPRISE_EMULATOR_HOST=... dart test \
//     test/integration_enterprise/pipeline_evaluation_property_test.dart \
//     --name "recorded emulator results"

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:test/test.dart';

import '../../../../../util/pipeline_evaluation_cases.dart';
import '../../../../../util/property_pipeline.dart';

void main() {
  test('the local evaluator returns what the emulator returned', () {
    final LocalEvaluation local = LocalEvaluation(
      DatabaseId.forProject(evaluationCasesProject),
    );
    final List<Expression> expressions = evaluationCases();
    final List<String> recorded = File(evaluationCasesGolden).readAsLinesSync();
    expect(
      recorded,
      hasLength(expressions.length),
      reason: 'The list of cases changed: record the results again',
    );

    int compared = 0;
    int rejected = 0;
    final List<String> unsupported = <String>[];
    final List<String> differences = <String>[];
    for (int i = 0; i < expressions.length; i++) {
      final Map<String, Object?> line =
          jsonDecode(recorded[i]) as Map<String, Object?>;
      final String description = '${expressions[i]}'.replaceAll('\n', ' ');
      expect(
        line['expression'],
        description,
        reason: 'Case $i changed: record the results again',
      );
      final String result = line['result']! as String;
      if (result == 'REJECTED' || result.startsWith('FAILED ')) {
        // The emulator refuses the pipeline before it runs it, or fails
        // running it (a defect of the emulator): there is no result to
        // compare with.
        rejected++;
        continue;
      }
      final EvaluateResult expected = local.decodeResult(
        line['result']! as String,
      );
      final EvaluateResult actual;
      try {
        actual = local.evaluate(
          expressions[i],
          evaluationCaseDocumentPath,
          evaluationCaseDocument,
        );
      } on UnsupportedExpression {
        unsupported.add(description);
        continue;
      }
      compared++;
      final model.FieldValue? a = actual.value;
      final model.FieldValue? e = expected.value;
      final bool same = a != null && e != null
          ? sameValue(a, e)
          : actual.isError == expected.isError &&
                actual.isUnset == expected.isUnset &&
                a == null &&
                e == null;
      if (!same) {
        differences.add(
          '$description\n    local    ${describeResult(actual)}\n'
          '    emulator ${describeResult(expected)}',
        );
      }
    }
    expect(
      differences,
      isEmpty,
      reason:
          '${differences.length} of $compared results differ:\n'
          '${differences.take(60).join('\n')}',
    );
    // What the evaluator refuses to evaluate (the caller then has to ask the
    // backend): a flag in the middle of a regular expression.
    expect(unsupported, hasLength(4), reason: unsupported.join('\n'));
    expect(unsupported, everyElement(contains('yummy (?i)good')));
    expect(compared, greaterThan(3000));
    // Only a few cases are rejected (a literal of the wrong kind).
    expect(rejected, lessThan(compared ~/ 10));
  });
}
