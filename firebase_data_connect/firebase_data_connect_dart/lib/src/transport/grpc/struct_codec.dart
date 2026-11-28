import 'package:firebase_data_connect_dart/src/errors.dart';
import 'package:firebase_data_connect_dart/src/proto/google/protobuf/index.dart'
    as pb;
import 'package:firebase_data_connect_dart/src/proto/index.dart' as pb;
import 'package:firebase_data_connect_dart/src/proto/google/rpc/index.dart'
    as rpc;
import 'package:firebase_data_connect_dart/src/value/json_values.dart';

/// Encodes validated [variables] (5.7 rules 1 and 3) as a `Struct`.
///
/// Numbers become `number_value`, `null` becomes `NULL_VALUE`. Throws an [ArgumentError] for a
/// value that is not a JSON value; the variables are validated before they reach the transport, so
/// that is a defect.
pb.Struct encodeStruct(Map<String, Object?> variables) {
  final pb.Struct struct = pb.Struct();
  variables.forEach((String key, Object? value) {
    struct.fields[key] = _encodeValue(value);
  });
  return struct;
}

pb.Value _encodeValue(Object? value) {
  if (value == null) {
    return pb.Value(nullValue: pb.NullValue.NULL_VALUE);
  }
  if (value is bool) {
    return pb.Value(boolValue: value);
  }
  if (value is num) {
    return pb.Value(numberValue: value.toDouble());
  }
  if (value is String) {
    return pb.Value(stringValue: value);
  }
  if (value is List<Object?>) {
    return pb.Value(listValue: pb.ListValue(values: value.map(_encodeValue)));
  }
  if (value is Map<String, Object?>) {
    return pb.Value(structValue: encodeStruct(value));
  }
  throw ArgumentError('a variable is not a JSON value');
}

/// Decodes [struct] into a fresh map (5.7 rules 4 and 6).
///
/// `number_value` becomes an `int` when it is finite, integral and within ±(2^53 - 1), else a
/// `double`; `null_value` and an unset `Value` become null. Throws a [FormatException], holding no
/// data, for a non-finite number or a value deeper than [maxDataDepth].
Map<String, Object?> decodeStruct(pb.Struct struct) => _decodeStruct(struct, 1);

Map<String, Object?> _decodeStruct(pb.Struct struct, int depth) {
  _checkDepth(depth);
  final Map<String, Object?> map = <String, Object?>{};
  for (final MapEntry<String, pb.Value> entry in struct.fields.entries) {
    map[entry.key] = _decodeValue(entry.value, depth);
  }
  return map;
}

List<Object?> _decodeList(pb.ListValue list, int depth) {
  _checkDepth(depth);
  final List<Object?> values = <Object?>[];
  for (final pb.Value value in list.values) {
    values.add(_decodeValue(value, depth));
  }
  return values;
}

/// Decodes [value], which sits inside a map or list of depth [depth].
Object? _decodeValue(pb.Value value, int depth) {
  switch (value.whichKind()) {
    case pb.Value_Kind.nullValue:
    case pb.Value_Kind.notSet:
      return null;
    case pb.Value_Kind.numberValue:
      return resultNumber(value.numberValue);
    case pb.Value_Kind.stringValue:
      return value.stringValue;
    case pb.Value_Kind.boolValue:
      return value.boolValue;
    case pb.Value_Kind.structValue:
      return _decodeStruct(value.structValue, depth + 1);
    case pb.Value_Kind.listValue:
      return _decodeList(value.listValue, depth + 1);
  }
}

void _checkDepth(int depth) {
  if (depth > maxDataDepth) {
    throw const FormatException('the result is deeper than the limit');
  }
}

/// Converts the error [error] into the model of 5.9.
///
/// `path` entries must be strings or integral non-negative numbers, otherwise `path` is empty and
/// the error kept (5.7 rule 7). The extensions are a map with the proto3-JSON names, without
/// default values (5.9).
GraphqlError decodeGraphqlError(pb.GraphqlError error) {
  return GraphqlError(
    message: error.message,
    path: error.hasPath()
        ? errorPathOf(_pathEntries(error.path))
        : const <Object>[],
    locations: <SourceLocation>[
      for (final pb.SourceLocation location in error.locations)
        SourceLocation(location.line, location.column),
    ],
    extensions: error.hasExtensions()
        ? _decodeExtensions(error.extensions)
        : const <String, Object?>{},
  );
}

/// The entries of [path] as `errorPathOf` reads them: strings and numbers as they are, any other
/// kind as null, which makes the path empty.
List<Object?> _pathEntries(pb.ListValue path) {
  return <Object?>[
    for (final pb.Value value in path.values)
      switch (value.whichKind()) {
        pb.Value_Kind.stringValue => value.stringValue,
        pb.Value_Kind.numberValue => value.numberValue,
        _ => null,
      },
  ];
}

Map<String, Object?> _decodeExtensions(pb.GraphqlErrorExtensions extensions) {
  final Map<String, Object?> map = <String, Object?>{};
  if (extensions.file.isNotEmpty) {
    map['file'] = extensions.file;
  }
  if (extensions.code != rpc.Code.OK) {
    map['code'] = extensions.code.name;
  }
  if (extensions.debugDetails.isNotEmpty) {
    map['debugDetails'] = extensions.debugDetails;
  }
  if (extensions.resource.isNotEmpty) {
    map['resource'] = extensions.resource;
  }
  if (extensions.warningLevel != pb.WarningLevel.WARNING_LEVEL_UNKNOWN) {
    map['warningLevel'] = extensions.warningLevel.name;
  }
  if (extensions.workarounds.isNotEmpty) {
    map['workarounds'] = <Map<String, Object?>>[
      for (final pb.Workaround workaround in extensions.workarounds)
        _decodeWorkaround(workaround),
    ];
  }
  return map;
}

Map<String, Object?> _decodeWorkaround(pb.Workaround workaround) {
  return <String, Object?>{
    if (workaround.description.isNotEmpty)
      'description': workaround.description,
    if (workaround.reason.isNotEmpty) 'reason': workaround.reason,
    if (workaround.replace.isNotEmpty) 'replace': workaround.replace,
  };
}
