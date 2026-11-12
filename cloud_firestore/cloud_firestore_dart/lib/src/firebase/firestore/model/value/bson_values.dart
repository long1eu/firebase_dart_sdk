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

part of field_value;

/// The reserved map keys of the BSON types.
///
/// On the wire each of these types is a map with a single reserved key, see
/// the model classes below for the shape of the value stored under it.
class BsonKeys {
  BsonKeys._();

  static const String minKey = '__min__';
  static const String maxKey = '__max__';
  static const String int32 = '__int__';
  static const String decimal128 = '__decimal128__';
  static const String objectId = '__oid__';
  static const String timestamp = '__request_timestamp__';
  static const String timestampSeconds = 'seconds';
  static const String timestampIncrement = 'increment';
  static const String regex = '__regex__';
  static const String regexPattern = 'pattern';
  static const String regexOptions = 'options';
  static const String binary = '__binary__';
}

/// The "Min Key" value, encoded as `{__min__: null}`. It sorts right after
/// null and all its instances are equal.
class MinKeyValue extends FieldValue {
  const MinKeyValue._();

  factory MinKeyValue.instance() => _instance;

  static const MinKeyValue _instance = MinKeyValue._();

  @override
  int get typeOrder => FieldValue.typeOrderMinKey;

  @override
  MinKey get value => MinKey.instance;

  @override
  int compareTo(FieldValue other) {
    return other is MinKeyValue ? 0 : defaultCompareTo(other);
  }

  @override
  bool operator ==(Object other) => other is MinKeyValue;

  @override
  int get hashCode => 0x6d696e;

  @override
  String toString() => '{${BsonKeys.minKey}:null}';
}

/// The "Max Key" value, encoded as `{__max__: null}`. It sorts after every
/// other value and all its instances are equal.
class MaxKeyValue extends FieldValue {
  const MaxKeyValue._();

  factory MaxKeyValue.instance() => _instance;

  static const MaxKeyValue _instance = MaxKeyValue._();

  @override
  int get typeOrder => FieldValue.typeOrderMaxKey;

  @override
  MaxKey get value => MaxKey.instance;

  @override
  int compareTo(FieldValue other) {
    return other is MaxKeyValue ? 0 : defaultCompareTo(other);
  }

  @override
  bool operator ==(Object other) => other is MaxKeyValue;

  @override
  int get hashCode => 0x6d6178;

  @override
  String toString() => '{${BsonKeys.maxKey}:null}';
}

/// A 32-bit integer, encoded as `{__int__: <integer>}`. It sorts with the
/// other numbers, by its numeric value.
class Int32FieldValue extends NumberValue {
  const Int32FieldValue(this._value);

  factory Int32FieldValue.valueOf(Int32Value value) => Int32FieldValue(value);

  final Int32Value _value;

  @override
  Int32Value get value => _value;

  int get intValue => _value.value;

  @override
  int compareTo(FieldValue other) {
    if (other is Decimal128FieldValue) {
      return -other.compareTo(this);
    } else if (other is Int32FieldValue) {
      return intValue.compareTo(other.intValue);
    } else if (other is NumberValue) {
      // 64-bit integers and doubles know how to compare with an integer.
      return IntegerValue(intValue).compareTo(other);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Int32FieldValue && intValue == other.intValue;

  @override
  int get hashCode => Object.hash(Int32FieldValue, intValue);

  @override
  String toString() => '{${BsonKeys.int32}:$intValue}';
}

/// A 128-bit decimal, encoded as `{__decimal128__: <string>}`. It sorts with
/// the other numbers, by its exact numeric value.
class Decimal128FieldValue extends NumberValue {
  Decimal128FieldValue(this._value)
      : number = ExactNumber.parse(_value.stringValue);

  factory Decimal128FieldValue.valueOf(Decimal128Value value) =>
      Decimal128FieldValue(value);

  final Decimal128Value _value;

  /// The exact numeric value of the decimal.
  final ExactNumber number;

  @override
  Decimal128Value get value => _value;

  bool get isNaN => number.isNaN;

  /// The closest double.
  double get doubleValue => number.toDouble();

  @override
  int compareTo(FieldValue other) {
    if (other is Decimal128FieldValue) {
      return number.compareTo(other.number);
    } else if (other is Int32FieldValue) {
      return number.compareTo(ExactNumber.fromInt(other.intValue));
    } else if (other is IntegerValue) {
      return number.compareTo(ExactNumber.fromInt(other.value));
    } else if (other is DoubleValue) {
      return number.compareTo(ExactNumber.fromDouble(other.value));
    } else {
      return defaultCompareTo(other);
    }
  }

  /// Decimals are equal if they have the same numeric value: `1.0` equals `1`.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Decimal128FieldValue && number.compareTo(other.number) == 0;

  @override
  int get hashCode => Object.hash(Decimal128FieldValue, number.decimalHashCode);

  @override
  String toString() => '{${BsonKeys.decimal128}:${_value.stringValue}}';
}

/// A BSON ObjectId, encoded as `{__oid__: <string>}`. It sorts between
/// references and geo points.
class BsonObjectIdValue extends FieldValue {
  const BsonObjectIdValue(this._value);

  factory BsonObjectIdValue.valueOf(BsonObjectId value) =>
      BsonObjectIdValue(value);

  final BsonObjectId _value;

  @override
  int get typeOrder => FieldValue.typeOrderBsonObjectId;

  @override
  BsonObjectId get value => _value;

  @override
  int compareTo(FieldValue other) {
    if (other is BsonObjectIdValue) {
      return compareUtf8Strings(_value.value, other._value.value);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BsonObjectIdValue && _value == other._value;

  @override
  int get hashCode => Object.hash(BsonObjectIdValue, _value);

  @override
  String toString() => '{${BsonKeys.objectId}:${_value.value}}';
}

/// A BSON timestamp, encoded as
/// `{__request_timestamp__: {seconds: <integer>, increment: <integer>}}`. It
/// sorts between timestamps and strings.
class BsonTimestampValue extends FieldValue {
  const BsonTimestampValue(this._value);

  factory BsonTimestampValue.valueOf(BsonTimestamp value) =>
      BsonTimestampValue(value);

  final BsonTimestamp _value;

  @override
  int get typeOrder => FieldValue.typeOrderBsonTimestamp;

  @override
  BsonTimestamp get value => _value;

  @override
  int compareTo(FieldValue other) {
    if (other is BsonTimestampValue) {
      final int cmp = _value.seconds.compareTo(other._value.seconds);
      if (cmp != 0) {
        return cmp;
      }
      return _value.increment.compareTo(other._value.increment);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BsonTimestampValue && _value == other._value;

  @override
  int get hashCode => Object.hash(BsonTimestampValue, _value);

  @override
  String toString() => '{${BsonKeys.timestamp}:{'
      '${BsonKeys.timestampIncrement}:${_value.increment},'
      '${BsonKeys.timestampSeconds}:${_value.seconds}}}';
}

/// A regular expression, encoded as
/// `{__regex__: {pattern: <string>, options: <string>}}`. It sorts between
/// geo points and arrays, by pattern and then by options.
class RegexFieldValue extends FieldValue {
  const RegexFieldValue(this._value);

  factory RegexFieldValue.valueOf(RegexValue value) => RegexFieldValue(value);

  final RegexValue _value;

  @override
  int get typeOrder => FieldValue.typeOrderRegex;

  @override
  RegexValue get value => _value;

  @override
  int compareTo(FieldValue other) {
    if (other is RegexFieldValue) {
      final int cmp = compareUtf8Strings(_value.pattern, other._value.pattern);
      if (cmp != 0) {
        return cmp;
      }
      return compareUtf8Strings(_value.options, other._value.options);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegexFieldValue && _value == other._value;

  @override
  int get hashCode => Object.hash(RegexFieldValue, _value);

  @override
  String toString() => '{${BsonKeys.regex}:{'
      '${BsonKeys.regexOptions}:${_value.options},'
      '${BsonKeys.regexPattern}:${_value.pattern}}}';
}

/// Replaces every map in [value] that has the encoded shape of a BSON value
/// (for example `{__int__: 5}`) with that BSON value, in [value] itself and
/// inside of its arrays and maps.
///
/// The backend does not tell such a map from the BSON value, both have the
/// same encoding. This is for values that do not come out of the serializer,
/// which already reads these maps as BSON values.
FieldValue resolveBsonShapes(FieldValue value) {
  if (value is ArrayValue) {
    bool changed = false;
    final List<FieldValue> elements = <FieldValue>[];
    for (final FieldValue element in value.internalValue) {
      final FieldValue resolved = resolveBsonShapes(element);
      changed = changed || !identical(resolved, element);
      elements.add(resolved);
    }
    return changed ? ArrayValue.fromList(elements) : value;
  } else if (value is ObjectValue) {
    ObjectValue result = value;
    for (final MapEntry<String, FieldValue> entry in value.internalValue) {
      final FieldValue resolved = resolveBsonShapes(entry.value);
      if (!identical(resolved, entry.value)) {
        result = result.set(FieldPath.fromSingleSegment(entry.key), resolved);
      }
    }
    return _bsonValueOfShape(result) ?? result;
  }
  return value;
}

FieldValue? _bsonValueOfShape(ObjectValue object) {
  if (object.internalValue.length != 1) {
    return null;
  }
  final MapEntry<String, FieldValue> entry = object.internalValue.first;
  final FieldValue field = entry.value;
  switch (entry.key) {
    case BsonKeys.minKey:
      return field is NullValue ? MinKeyValue.instance() : null;
    case BsonKeys.maxKey:
      return field is NullValue ? MaxKeyValue.instance() : null;
    case BsonKeys.int32:
      if (field is IntegerValue &&
          field.value >= Int32Value.minValue &&
          field.value <= Int32Value.maxValue) {
        return Int32FieldValue.valueOf(Int32Value(field.value));
      }
      return null;
    case BsonKeys.decimal128:
      if (field is! StringValue) {
        return null;
      }
      try {
        return Decimal128FieldValue.valueOf(Decimal128Value(field.value));
      } on FormatException {
        return null;
      }
    case BsonKeys.objectId:
      return field is StringValue
          ? BsonObjectIdValue.valueOf(BsonObjectId(field.value))
          : null;
    case BsonKeys.binary:
      if (field is BlobValue) {
        final Blob blob = field.value;
        // A subtype of 0 is a regular blob, which is never encoded as a map.
        if (blob.subtype == 0 && blob.bytes.isNotEmpty && blob.bytes[0] != 0) {
          return BlobValue.valueOf(Blob.bsonBinary(
              blob.bytes[0], Uint8List.sublistView(blob.bytes, 1)));
        }
      }
      return null;
    case BsonKeys.timestamp:
      if (field is ObjectValue && field.internalValue.length == 2) {
        final FieldValue? seconds =
            field.internalValue[BsonKeys.timestampSeconds];
        final FieldValue? increment =
            field.internalValue[BsonKeys.timestampIncrement];
        if (seconds is IntegerValue &&
            increment is IntegerValue &&
            seconds.value >= 0 &&
            seconds.value <= BsonTimestamp.maxValue &&
            increment.value >= 0 &&
            increment.value <= BsonTimestamp.maxValue) {
          return BsonTimestampValue.valueOf(
              BsonTimestamp(seconds.value, increment.value));
        }
      }
      return null;
    case BsonKeys.regex:
      if (field is ObjectValue && field.internalValue.length == 2) {
        final FieldValue? pattern = field.internalValue[BsonKeys.regexPattern];
        final FieldValue? options = field.internalValue[BsonKeys.regexOptions];
        if (pattern is StringValue && options is StringValue) {
          return RegexFieldValue.valueOf(
              RegexValue(pattern.value, options.value));
        }
      }
      return null;
    default:
      return null;
  }
}
