// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:fixnum/fixnum.dart';
import 'package:meta/meta.dart';

/// One step of a pipeline, in the form it is sent to the server: a snake case
/// [name], positional [args] and named [options].
///
/// Not part of the public API; use the methods of `Pipeline`.
@internal
class Stage {
  Stage(
    this.name, {
    List<pb.Value Function(PipelineEncoder encoder)> args = const <pb.Value
        Function(PipelineEncoder)>[],
    Map<String, pb.Value Function(PipelineEncoder encoder)> options =
        const <String, pb.Value Function(PipelineEncoder)>{},
    Map<String, Object?>? rawOptions,
  })  : _args = args,
        _options = options,
        _rawOptions = rawOptions;

  final String name;
  final List<pb.Value Function(PipelineEncoder encoder)> _args;
  final Map<String, pb.Value Function(PipelineEncoder encoder)> _options;
  final Map<String, Object?>? _rawOptions;

  pb.Pipeline_Stage toProto(PipelineEncoder encoder) {
    final pb.Pipeline_Stage stage = pb.Pipeline_Stage()..name = name;
    for (final pb.Value Function(PipelineEncoder) arg in _args) {
      stage.args.add(arg(encoder));
    }
    _options.forEach((String key, pb.Value Function(PipelineEncoder) value) {
      stage.options[key] = value(encoder);
    });
    // Raw options are applied last so that they can override known options.
    stage.options.addAll(encodeOptions(encoder, _rawOptions));
    return stage;
  }

  @override
  String toString() => 'Stage($name)';
}

/// Encodes user supplied option values; expressions are allowed as values.
@internal
Map<String, pb.Value> encodeOptions(
    PipelineEncoder encoder, Map<String, Object?>? options) {
  final Map<String, pb.Value> result = <String, pb.Value>{};
  options?.forEach((String key, Object? value) {
    result[key] = value is Expression
        ? value.toProto(encoder)
        : encoder.encodeUserValue(value);
  });
  return result;
}

/// Encodes a map of named expressions (the argument of `select`,
/// `add_fields`, `aggregate`, ...).
@internal
pb.Value encodeExpressionMap(
    PipelineEncoder encoder, Map<String, Expression> expressions) {
  final pb.MapValue map = pb.MapValue();
  expressions.forEach((String alias, Expression expression) {
    map.fields[alias] = expression.toProto(encoder);
  });
  return pb.Value()..mapValue = map;
}

@internal
pb.Value stringValue(String value) => pb.Value()..stringValue = value;

@internal
pb.Value integerValue(int value) => pb.Value()..integerValue = Int64(value);

@internal
pb.Value doubleValue(double value) => pb.Value()..doubleValue = value;

/// A reference relative to the database root, the way pipelines address
/// collections and documents (`/users/alice`).
@internal
pb.Value relativeReferenceValue(String path) {
  return pb.Value()..referenceValue = path.startsWith('/') ? path : '/$path';
}

/// Turns a list of `String` field names and [Selectable]s into a map from
/// output name to expression. Fails on duplicate names, because the second
/// entry would silently replace the first on the wire.
@internal
Map<String, Expression> selectablesToMap(List<Object> selectables,
    {required String method}) {
  final Map<String, Expression> result = <String, Expression>{};
  for (final Object selectable in selectables) {
    final String alias;
    final Expression expression;
    if (selectable is String) {
      final Field field = Field.of(selectable);
      alias = field.alias;
      expression = field;
    } else if (selectable is Selectable) {
      alias = selectable.alias;
      expression = selectable.expression;
    } else {
      throw ArgumentError(
          '$method() takes field names (String) and Selectables (a Field or '
          'an expression with an alias), but got: $selectable');
    }
    if (result.containsKey(alias)) {
      throw ArgumentError("Duplicate alias or field '$alias' in $method().");
    }
    result[alias] = expression;
  }
  return result;
}
