// The differences between local pipeline evaluation and the Enterprise
// edition emulator that are known and explained, shared by the property
// tests of expressions and of whole pipelines.

import 'property_pipeline_stages.dart';

/// A difference between the local evaluator and the emulator that is
/// understood: the reason, or null for a difference that fails the test.
///
/// Keep this list short and every entry explained: it is the list of what
/// local evaluation does differently on purpose or can not do.
String? knownDifference(
  String expression,
  String document,
  String local,
  String remote,
) {
  if (_mapParts.hasMatch(expression)) {
    return 'the order of the keys of a map that an expression built '
        '(map_set, map_merge, map_remove, map) is not specified: the '
        'emulator returns them as its hash map has them, the evaluator '
        'sorted';
  }
  return null;
}

/// Why the emulator fails with an error that is not INVALID_ARGUMENT (the
/// whole pipeline fails, also inside `if_error`) for [expression], or null
/// when that is not a known defect.
String? knownEmulatorFailure(String expression) {
  if (_splitOfConcat.hasMatch(expression)) {
    return 'emulator: split() with string_concat(), concat() or join() '
        'somewhere in its value or delimiter fails the pipeline with '
        'INTERNAL, whatever the documents are';
  }
  if (expression.contains('mod(') &&
      (expression.contains('Decimal128') ||
          expression.contains('Field(dec)'))) {
    return 'emulator: mod() of decimal128 numbers whose integer quotient has '
        'more than 34 digits fails the pipeline with INTERNAL; the evaluator '
        'returns the exact remainder';
  }
  if (expression.contains('round(') &&
      (expression.contains('Decimal128') ||
          expression.contains('Field(dec)'))) {
    return 'emulator: round(decimal128, places) of a value between -1 and 1 '
        'fails the pipeline with INTERNAL; the evaluator rounds it';
  }
  return null;
}

final RegExp _splitOfConcat = RegExp(
  r'split\(.*\b(string_concat|concat|join)\(',
);
final RegExp _mapParts = RegExp(r'map_(keys|values|entries)\(');

/// A difference between the local pipeline executor and the emulator for a
/// whole pipeline ([description] lists its stages) that is understood: the
/// reason, or null. [local] or [remote] is null for a pipeline that failed
/// there.
String? knownPipelineDifference(
  String description,
  List<PipelineRow>? local,
  List<PipelineRow>? remote, {
  required bool ordered,
}) {
  final String? expression = knownDifference(description, '', '', '');
  if (expression != null) {
    return expression;
  }
  if (remote == null && local != null) {
    final String? failure = knownEmulatorFailure(description);
    if (failure != null) {
      return failure;
    }
  }
  if (local != null &&
      remote != null &&
      (description.contains('distinct(') ||
          description.contains('groups: [') &&
              !description.contains('groups: []')) &&
      sameRows(local, remote, ordered: ordered, loose: true)) {
    return 'which of equal values (1 and 1.0, 0 and -0.0, null and a missing '
        'value) a group of distinct() or aggregate() shows is not specified';
  }
  return null;
}
