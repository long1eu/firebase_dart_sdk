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
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/stage.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:meta/meta.dart';

/// The inputs, relative to the current one, that a window function of
/// `Pipeline.addWindowFields` is evaluated over.
///
/// Each bound is a number, [current], [unbounded] or an [Expression] that
/// evaluates to one of those. A bound that is not given is the current input
/// (the server default).
///
/// **Beta**: window functions are a preview feature of the server; the
/// Enterprise emulator rejects them.
class WindowFrame {
  /// A frame of inputs counted by position: [preceding] inputs before the
  /// current one up to [following] inputs after it. `current` is the
  /// position of the current input only (ties are not included). A negative
  /// [preceding] starts the frame after the current input; a negative
  /// [following] ends it before.
  WindowFrame.documents({Object? preceding, Object? following})
    : this._('documents', preceding, following, null);

  /// A frame of inputs by the value of the (single) sort key of the window:
  /// the inputs whose sort value is at most [preceding] below and at most
  /// [following] above that of the current input. `current` includes the
  /// inputs tied with the current one.
  ///
  /// [unit] (`'microsecond'`, `'millisecond'`, `'second'`, `'minute'`,
  /// `'hour'`, `'day'`, `'week'`, `'month'`, `'quarter'`, `'year'` or an
  /// [Expression]) makes the offsets durations, for a timestamp sort key.
  WindowFrame.range({Object? preceding, Object? following, Object? unit})
    : this._('range', preceding, following, unit);

  WindowFrame._(this.kind, this.preceding, this.following, this.unit) {
    _checkBound(preceding, 'preceding');
    _checkBound(following, 'following');
    if (unit != null && unit is! String && unit is! Expression) {
      throw ArgumentError.value(
        unit,
        'unit',
        'must be a String or an Expression',
      );
    }
  }

  /// The bound for the current input.
  static const String current = 'current';

  /// The bound for the first or the last input of the partition.
  static const String unbounded = 'unbounded';

  /// `documents` or `range`: the key of this frame on the wire.
  @internal
  final String kind;

  /// The start of the frame, or null for the server default.
  final Object? preceding;

  /// The end of the frame, or null for the server default.
  final Object? following;

  /// The unit of the offsets of a range frame, or null.
  final Object? unit;

  static void _checkBound(Object? bound, String name) {
    if (bound == null || bound is num || bound is Expression) {
      return;
    }
    if (bound is String) {
      // Like the JS SDK, any string is passed through so that the server can
      // add bounds; it rejects the ones it does not know.
      return;
    }
    throw ArgumentError.value(
      bound,
      name,
      "must be a number, 'current', 'unbounded' or an Expression",
    );
  }

  static pb.Value _boundToProto(PipelineEncoder encoder, Object bound) {
    if (bound is int) {
      return integerValue(bound);
    } else if (bound is double) {
      return doubleValue(bound);
    } else if (bound is String) {
      return stringValue(bound);
    }
    return (bound as Expression).toProto(encoder);
  }

  /// The wire form: a map with `preceding`, `following` and `unit`, each only
  /// when given.
  @internal
  pb.Value toProto(PipelineEncoder encoder) {
    final pb.MapValue map = pb.MapValue();
    final Object? preceding = this.preceding;
    final Object? following = this.following;
    final Object? unit = this.unit;
    if (preceding != null) {
      map.fields['preceding'] = _boundToProto(encoder, preceding);
    }
    if (following != null) {
      map.fields['following'] = _boundToProto(encoder, following);
    }
    if (unit != null) {
      map.fields['unit'] = unit is String
          ? stringValue(unit)
          : (unit as Expression).toProto(encoder);
    }
    return pb.Value()..mapValue = map;
  }

  @override
  String toString() =>
      'WindowFrame.$kind(preceding: $preceding, following: $following'
      '${unit == null ? '' : ', unit: $unit'})';
}

/// How `Pipeline.addWindowFields` groups and orders the inputs, and the
/// default frame of its window functions.
///
/// Without [frame], an unsorted window covers the whole partition and a
/// sorted one runs from the start of the partition up to the inputs tied with
/// the current one.
///
/// **Beta**: window functions are a preview feature of the server.
class WindowSpec {
  /// A window over the [partition] keys (field names as `String`s or
  /// expressions), ordered by [sort], with the default [frame].
  const WindowSpec({
    this.partition = const <Object>[],
    this.sort = const <Ordering>[],
    this.frame,
  });

  /// The keys that split the inputs into independent partitions.
  final List<Object> partition;

  /// The order of the inputs inside a partition.
  final List<Ordering> sort;

  /// The frame of the window functions, or null for the default.
  final WindowFrame? frame;

  /// The wire form: a map with `partition`, `sort` and the frame keyed by its
  /// kind; empty lists are left out.
  @internal
  pb.Value toProto(PipelineEncoder encoder) {
    final pb.MapValue map = pb.MapValue();
    if (partition.isNotEmpty) {
      map.fields['partition'] = pb.Value()
        ..arrayValue = (pb.ArrayValue()
          ..values.addAll(
            partition.map(
              (Object key) => fieldOrExpression(key).toProto(encoder),
            ),
          ));
    }
    if (sort.isNotEmpty) {
      map.fields['sort'] = pb.Value()
        ..arrayValue = (pb.ArrayValue()
          ..values.addAll(
            sort.map((Ordering ordering) => ordering.toProto(encoder)),
          ));
    }
    final WindowFrame? frame = this.frame;
    if (frame != null) {
      map.fields[frame.kind] = frame.toProto(encoder);
    }
    return pb.Value()..mapValue = map;
  }

  @override
  String toString() =>
      'WindowSpec(partition: $partition, sort: $sort, frame: $frame)';
}

/// A function evaluated over a frame of inputs, for
/// `Pipeline.addWindowFields`: a ranking function such as `rank()`, or an
/// [AggregateFunction] with a frame (`AggregateFunction.over`).
///
/// Create it directly to call a window function this SDK has no helper for.
///
/// **Beta**: window functions are a preview feature of the server.
class WindowFunction {
  /// A call of the server window function [name] (snake case) with [args],
  /// evaluated over the frame of the enclosing stage.
  WindowFunction(this.name, [List<Object?> args = const <Object?>[]])
    : args = List<Expression>.unmodifiable(args.map(toExpression)),
      frame = null;

  /// A call of [name] with [args] over its own [frame].
  @internal
  WindowFunction.withFrame(this.name, List<Expression> args, this.frame)
    : args = List<Expression>.unmodifiable(args);

  /// The server name of the function.
  final String name;

  /// The arguments of the call.
  final List<Expression> args;

  /// The frame of this function, or null for the frame of the enclosing
  /// stage.
  final WindowFrame? frame;

  /// This function evaluated over [frame] instead of the frame of the
  /// enclosing stage.
  WindowFunction over(WindowFrame frame) =>
      WindowFunction.withFrame(name, args, frame);

  /// Names the result of this function.
  AliasedWindowFunction as(String alias) => AliasedWindowFunction(this, alias);

  /// The wire form: the call, wrapped in `over(call, {kind: frame})` when it
  /// has its own frame.
  @internal
  pb.Value toProto(PipelineEncoder encoder) {
    final pb.Value call = pb.Value()
      ..functionValue = (pb.Function_()
        ..name = name
        ..args.addAll(args.map((Expression e) => e.toProto(encoder))));
    final WindowFrame? frame = this.frame;
    if (frame == null) {
      return call;
    }
    return pb.Value()
      ..functionValue = (pb.Function_()
        ..name = 'over'
        ..args.addAll(<pb.Value>[
          call,
          pb.Value()
            ..mapValue = (pb.MapValue()
              ..fields[frame.kind] = frame.toProto(encoder)),
        ]));
  }

  @override
  String toString() =>
      '$name(${args.join(', ')})${frame == null ? '' : ' over $frame'}';
}

/// A [WindowFunction] with a name, created with [WindowFunction.as].
///
/// **Beta**: window functions are a preview feature of the server.
class AliasedWindowFunction {
  AliasedWindowFunction(this.windowFunction, this.alias);

  /// The function that produces the value.
  final WindowFunction windowFunction;

  /// The name of the output field.
  final String alias;

  @override
  String toString() => '$windowFunction as $alias';
}
