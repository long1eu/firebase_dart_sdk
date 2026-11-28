/// The canonical JSON text of variables, for `OperationRef.operationId` (spec 5.8, 5.10).
library;

import 'dart:convert';

/// [value] as JSON text with the keys of every map sorted, so equal values give equal text whatever
/// the order their maps were filled in.
///
/// [value] holds only JSON values, as `checkVariables` leaves them.
String canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) {
  return switch (value) {
    Map<Object?, Object?>() => <String, Object?>{
      for (final String key in value.keys.cast<String>().toList()..sort())
        key: _sorted(value[key]),
    },
    List<Object?>() => <Object?>[
      for (final Object? item in value) _sorted(item),
    ],
    _ => value,
  };
}

/// `operationName|<canonical JSON of variables>`, with `null` when there are no variables.
String operationIdOf(String operationName, Map<String, Object?>? variables) {
  final String encoded = variables == null ? 'null' : canonicalJson(variables);
  return '$operationName|$encoded';
}
