// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/server_timestamps.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/values.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart';

/// A structured object value stored in Firestore.
class ObjectValue {
  ObjectValue(this.proto) {
    hardAssert(proto.whichValueType() == Value_ValueType.mapValue, 'ObjectValues should be backed by a MapValue');
    hardAssert(!ServerTimestamps.isServerTimestamp(proto), 'ServerTimestamps should not be used as an ObjectValue');
  }

  ObjectValue.fromMap(Map<String, Value> value) : this(Value(mapValue: MapValue(fields: value)));

  factory ObjectValue.empty() => _emptyInstance;
  static final ObjectValue _emptyInstance = ObjectValue(Value(mapValue: MapValue()));

  /// Returns a new ObjectValueBuilder instance that is based on an empty object.
  static ObjectValueBuilder newBuilder() {
    return _emptyInstance.toBuilder();
  }

  /// Returns the Protobuf that backs this ObjectValue.
  final Value proto;

  Map<String, Value> get fields {
    return <String, Value>{...proto.mapValue.fields};
  }

  /// Recursively extracts the FieldPaths that are set in this ObjectValue.
  FieldMask get fieldMask {
    return _extractFieldMask(proto.mapValue);
  }

  FieldMask _extractFieldMask(MapValue value) {
    final Set<FieldPath> fields = <FieldPath>{};
    for (MapEntry<String, Value> entry in value.fields.entries) {
      final FieldPath currentPath = FieldPath.fromSingleSegment(entry.key);
      if (isMapValue(entry.value)) {
        final FieldMask nestedMask = _extractFieldMask(entry.value.mapValue);
        final Set<FieldPath> nestedFields = nestedMask.mask;
        if (nestedFields.isEmpty) {
          // Preserve the empty map by adding it to the FieldMask.
          fields.add(currentPath);
        } else {
          // For nested and non-empty ObjectValues, add the FieldPath of the leaf nodes.
          for (FieldPath nestedPath in nestedFields) {
            fields.add(currentPath.appendField(nestedPath));
          }
        }
      } else {
        fields.add(currentPath);
      }
    }
    return FieldMask(fields);
  }

  /// Returns the value at the given [fieldPath] or null.
  Value operator [](FieldPath fieldPath) {
    if (fieldPath.isEmpty) {
      return proto;
    } else {
      Value value = proto;
      for (int i = 0; i < fieldPath.length - 1; ++i) {
        value = value.mapValue.fields[fieldPath.getSegment(i)];
        if (!isMapValue(value)) {
          return null;
        }
      }
      return value.mapValue.fields[fieldPath.getLastSegment()];
    }
  }

  Value get(FieldPath fieldPath) {
    if (fieldPath.isEmpty) {
      return proto;
    } else {
      Value value = proto;
      for (int i = 0; i < fieldPath.length - 1; ++i) {
        value = value.mapValue.fields[fieldPath.getSegment(i)];
        if (!isMapValue(value)) {
          return null;
        }
      }
      return value.mapValue.fields[fieldPath.getLastSegment()];
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectValue && //
          runtimeType == other.runtimeType &&
          equals(proto, other.proto);

  @override
  int get hashCode => proto.hashCode;

  /// Creates a ObjectValueBuilder instance that is based on the current value.
  ObjectValueBuilder toBuilder() => ObjectValueBuilder(this);
}

/// An [ObjectValueBuilder] provides APIs to set and delete fields from an ObjectValue. All
/// operations mutate the existing instance.
class ObjectValueBuilder {
  ObjectValueBuilder(this._baseObject) : _overlayMap = <String, Object>{};

  /// The existing data to mutate.
  final ObjectValue _baseObject;

  /// A nested map that contains the accumulated changes in this ObjectValueBuilder. Values can either be
  /// [Value] protos, [Map<String, Object>] values (to represent additional nesting) or [null] (to
  /// represent field deletes).
  final Map<String, Object> _overlayMap;

  /// Sets the field to the provided value.
  operator []=(FieldPath path, Value value) {
    hardAssert(path.isNotEmpty, 'Cannot set field for empty path on ObjectValue');
    _setOverlay(path, value);
  }

  /// Removes the field at the specified path. If there is no field at the specified path nothing
  /// is changed.
  void delete(FieldPath path) {
    hardAssert(path.isNotEmpty, 'Cannot delete field for empty path on ObjectValue');
    _setOverlay(path, null);
  }

  /// Adds [value] to the overlay map at [path] creating nested map entries if needed.
  void _setOverlay(FieldPath path, Value value) {
    Map<String, Object> currentLevel = _overlayMap;

    for (int i = 0; i < path.length - 1; ++i) {
      final String currentSegment = path.getSegment(i);
      final Object currentValue = currentLevel[currentSegment];

      if (currentValue is Map) {
        // Re-use a previously created map
        currentLevel = currentValue;
      } else if (currentValue is Value && currentValue.whichValueType() == Value_ValueType.mapValue) {
        // Convert the existing Protobuf MapValue into a Java map
        final Map<String, Object> nextLevel = <String, Object>{...currentValue.mapValue.fields};
        currentLevel[currentSegment] = nextLevel;
        currentLevel = nextLevel;
      } else {
        // Create an empty hash map to represent the current nesting level
        final Map<String, Object> nextLevel = <String, Object>{};
        currentLevel[currentSegment] = nextLevel;
        currentLevel = nextLevel;
      }
    }

    currentLevel[path.getLastSegment()] = value;
  }

  /// Returns an [ObjectValue] with all mutations applied.
  ObjectValue build() {
    final MapValue mergedResult = _applyOverlay(FieldPath.emptyPath, _overlayMap);
    if (mergedResult != null) {
      return ObjectValue(Value(mapValue: mergedResult));
    } else {
      return _baseObject;
    }
  }

  /// Applies any overlays from [currentOverlays] that exist at [currentPath] and returns the
  /// merged data at [currentPath] (or null if there were no changes).
  ///
  /// The [currentPath] is the path at the current nesting level. Can be set to [FieldValue.EMPTY_PATH]
  /// to represent the root. The [currentOverlays] are the overlays at the current nesting level in the
  /// same format as [overlayMap].
  MapValue _applyOverlay(FieldPath currentPath, Map<String, Object> currentOverlays) {
    bool modified = false;

    final Value existingValue = _baseObject.get(currentPath);
    final MapValue resultAtPath = isMapValue(existingValue)
        // If there is already data at the current path, base our modifications on top
        // of the existing data.
        ? existingValue.mapValue.toBuilder()
        : MapValue();

    for (MapEntry<String, Object> entry in currentOverlays.entries) {
      final String pathSegment = entry.key;
      final Object value = entry.value;

      if (value is Map) {
        final MapValue nested = _applyOverlay(currentPath.appendSegment(pathSegment), value);
        if (nested != null) {
          resultAtPath.fields[pathSegment] = Value(mapValue: nested);
          modified = true;
        }
      } else if (value is Value) {
        resultAtPath.fields[pathSegment] = value;
        modified = true;
      } else if (resultAtPath.fields.containsKey(pathSegment)) {
        hardAssert(value == null, 'Expected entry to be a Map, a Value or null');
        resultAtPath.fields.remove(pathSegment);
        modified = true;
      }
    }

    return modified ? resultAtPath.freeze() : null;
  }
}
