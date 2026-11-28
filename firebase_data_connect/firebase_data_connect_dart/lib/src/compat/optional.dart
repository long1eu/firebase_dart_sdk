// Ported from FlutterFire firebase_data_connect 0.4.2 (commit 6a80b1b),
// lib/src/optional.dart. Apache License 2.0; see NOTICE. nativeToJson<DateTime> writes
// yyyy-MM-dd by hand instead of package:intl's DateFormat.

import 'package:firebase_data_connect_dart/src/compat/errors.dart';

/// Whether an [Optional] value was set.
enum OptionalState {
  /// Not set: the variable is left out of the request.
  unset,

  /// Set, possibly to null: the variable is sent.
  set,
}

/// A variable that can be left out of a request, or sent, possibly as null.
class Optional<T> {
  /// An unset optional with [deserializer] and [serializer].
  Optional(this.deserializer, this.serializer);

  /// An unset optional with [deserializer] and [serializer].
  Optional.optional(this.deserializer, this.serializer);

  /// Whether [value] was set. Unset by default.
  OptionalState state = OptionalState.unset;

  /// Turns the value into JSON.
  DynamicSerializer<T> serializer;

  /// Turns JSON into the value.
  DynamicDeserializer<T> deserializer;

  T? _value;

  /// Sets the value and the state to [OptionalState.set].
  set value(T? val) {
    _value = val;
    state = OptionalState.set;
  }

  /// The current value.
  T? get value => _value;

  /// Sets the value from [json] with the [deserializer].
  void fromJson(dynamic json) {
    if (json is List) {
      value = json.map((dynamic e) => deserializer(e)) as T;
    } else {
      value = deserializer(json as String);
    }
  }

  /// The value through the [serializer]; null when it was set to null; the empty string when it
  /// is unset.
  dynamic toJson() {
    final T? current = _value;
    if (current != null) {
      return serializer(current);
    }
    if (state == OptionalState.set) {
      return null;
    }
    return '';
  }
}

/// [type] as JSON: booleans, numbers and strings unchanged, a [DateTime] as `yyyy-MM-dd`.
///
/// Throws an [UnimplementedError] for any other type.
dynamic nativeToJson<T>(T type) {
  if (type is bool || type is num || type is String) {
    return type;
  }
  if (type is DateTime) {
    return _dateText(type);
  }
  throw UnimplementedError('This type is unimplemented: ${type.runtimeType}');
}

/// `yyyy-MM-dd` of [date] in its own time zone, each part zero-padded.
String _dateText(DateTime date) {
  final int year = date.year;
  final String yearText = year < 0
      ? '-${(-year).toString().padLeft(4, '0')}'
      : year.toString().padLeft(4, '0');
  final String month = date.month.toString().padLeft(2, '0');
  final String day = date.day.toString().padLeft(2, '0');
  return '$yearText-$month-$day';
}

/// [input] as a [T]: booleans and numbers of that type unchanged, a string as a [DateTime], a
/// [String] or an [int] (an `Int64` arrives as a string), and an `int` and a `double` converted
/// into each other.
///
/// Throws an [UnsupportedError] for an integer string out of the range of `int`, and an
/// [UnimplementedError] for any other combination.
T nativeFromJson<T>(dynamic input) {
  if ((input is bool && T == bool) ||
      (input is int && T == int) ||
      (input is double && T == double) ||
      (input is num && T == num)) {
    return input as T;
  }
  if (input is String) {
    if (T == DateTime) {
      return DateTime.parse(input) as T;
    }
    if (T == String) {
      return input as T;
    }
    if (T == int) {
      final BigInt value = BigInt.parse(input);
      if (!value.isValidInt) {
        throw UnsupportedError('BigInt ($input) too large for Dart int');
      }
      return value.toInt() as T;
    }
  } else if (input is double && T == int) {
    return input.toInt() as T;
  } else if (input is int && T == double) {
    return input.toDouble() as T;
  }
  throw UnimplementedError('This type is unimplemented: $T');
}

/// A deserializer of a list whose elements [deserializer] reads.
DynamicDeserializer<List<T>> listDeserializer<T>(
  DynamicDeserializer<T> deserializer,
) {
  return (dynamic data) =>
      (data as List<T>).map((dynamic e) => deserializer(e)).toList();
}

/// A serializer of a list whose elements [serializer] writes.
DynamicSerializer<List<T>> listSerializer<T>(DynamicSerializer<T> serializer) {
  return (dynamic data) =>
      (data as List<T>).map((dynamic e) => serializer(e)).toList();
}
