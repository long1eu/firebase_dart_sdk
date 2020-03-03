// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value_options.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';

class ObjectValue extends FieldValue {
  const ObjectValue(this._value);

  factory ObjectValue.fromMap(Map<String, FieldValue> value) {
    return ObjectValue.fromImmutableMap(
        ImmutableSortedMap<String, FieldValue>.fromMap(value, comparator()));
  }

  factory ObjectValue.fromImmutableMap(ImmutableSortedMap<String, FieldValue> value) {
    if (value.isEmpty) {
      return empty;
    } else {
      return ObjectValue(value);
    }
  }

  static final ObjectValue empty =
      ObjectValue(ImmutableSortedMap<String, FieldValue>.emptyMap(comparator()));

  final ImmutableSortedMap<String, FieldValue> _value;

  @override
  int get typeOrder => FieldValue.typeOrderObject;

  @override
  Map<String, Object> get value {
    final Map<String, Object> res = <String, Object>{};
    for (MapEntry<String, FieldValue> entry in _value) {
      res[entry.key] = entry.value.value;
    }
    return res;
  }

  ImmutableSortedMap<String, FieldValue> get internalValue => _value;

  @override
  Map<String, Object> valueWith(FieldValueOptions options) {
    final Map<String, Object> res = <String, Object>{};
    for (MapEntry<String, FieldValue> entry in _value) {
      res[entry.key] = entry.value.valueWith(options);
    }
    return res;
  }

  @override
  int compareTo(FieldValue other) {
    if (other is ObjectValue) {
      for (int i = 0; i < _value.length && i < other._value.length; i++) {
        final MapEntry<String, FieldValue> entry1 = _value.elementAt(i);
        final MapEntry<String, FieldValue> entry2 = other._value.elementAt(i);

        final int keyCompare = entry1.key.compareTo(entry2.key);
        if (keyCompare != 0) {
          return keyCompare;
        }

        final int valueCompare = entry1.value.compareTo(entry2.value);

        if (valueCompare != 0) {
          return valueCompare;
        }
      }

      return _value.length.compareTo(other._value.length);
    } else {
      return defaultCompareTo(other);
    }
  }

  /// Returns a new ObjectValue with the field at the named path set to value.
  ObjectValue set(FieldPath path, FieldValue value) {
    hardAssert(path.isNotEmpty, 'Cannot set field for empty path on ObjectValue');

    final String childName = path.first;
    if (path.length == 1) {
      return _setChild(childName, value);
    } else {
      final FieldValue child = internalValue[childName];
      ObjectValue obj;
      if (child is ObjectValue) {
        obj = child;
      } else {
        obj = ObjectValue.empty;
      }

      final ObjectValue newChild = obj.set(path.popFirst(), value);
      return _setChild(childName, newChild);
    }
  }

  /// Returns an ObjectValue with the field path deleted. If there is no field at the specified path
  /// nothing is changed.
  ObjectValue delete(FieldPath path) {
    hardAssert(path.isNotEmpty, 'Cannot delete field for empty path on ObjectValue');

    final String childName = path.first;
    if (path.length == 1) {
      return ObjectValue.fromImmutableMap(_value.remove(childName));
    } else {
      final FieldValue child = _value[childName];
      if (child is ObjectValue) {
        final ObjectValue newChild = child.delete(path.popFirst());
        return _setChild(childName, newChild);
      } else {
        // Don't actually change a primitive value to an object for a delete.
        return this;
      }
    }
  }

  /// Returns the value at the given path or null
  FieldValue get(FieldPath fieldPath) {
    FieldValue current = this;

    for (int i = 0; i < fieldPath.length; i++) {
      if (current is ObjectValue) {
        final ObjectValue object = current;
        current = object._value[fieldPath[i]];
      } else {
        return null;
      }
    }

    return current;
  }

  ObjectValue _setChild(String childName, FieldValue value) {
    return ObjectValue.fromImmutableMap(internalValue.insert(childName, value));
  }

  @override
  String toString() => _value.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectValue && runtimeType == other.runtimeType && _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}
