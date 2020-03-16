// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/document.pb.dart';
import 'package:cloud_firestore_vm/src/proto/index.dart' as pb;

typedef Converter = FieldValue Function(Value value);

/// Describes the hasPendingWrites state of a document.
enum DocumentState {
  /// Local mutations applied via the mutation queue. Document is potentially inconsistent.
  localMutations,

  /// Mutations applied based on a write acknowledgment. Document is potentially inconsistent.
  committedMutations,

  /// No mutations applied. Document was sent to us by Watch.
  synced
}

class Document extends MaybeDocument implements Comparable<Document> {
  Document(
    DocumentKey key,
    SnapshotVersion version,
    this.documentState,
    this._objectValue,
  )   : proto = null,
        converter = null,
        super(key, version);

  Document.fromProto(
    DocumentKey key,
    SnapshotVersion version,
    this.documentState,
    this.proto,
    this.converter,
  )   : _objectValue = null,
        super(key, version);

  final DocumentState documentState;
  final pb.Document proto;
  final Converter converter;

  /// A cache for FieldValues that have already been deserialized in [getField]
  Map<FieldPath, FieldValue> _fieldValueCache;
  ObjectValue _objectValue;

  ObjectValue get data {
    if (_objectValue == null) {
      hardAssert(proto != null && converter != null,
          'Expected proto and converter to be non-null');

      ObjectValue result = ObjectValue.empty;
      for (MapEntry<String, Value> entry in proto.fields.entries) {
        final FieldPath path = FieldPath.fromSingleSegment(entry.key);
        final FieldValue value = converter(entry.value);
        result = result.set(path, value);
      }
      _objectValue = result;

      // Once objectValue is computed, values inside the fieldValueCache are no
      // longer accessed.
      _fieldValueCache = null;
    }

    return _objectValue;
  }

  FieldValue getField(FieldPath path) {
    if (_objectValue != null) {
      return _objectValue.get(path);
    } else {
      hardAssert(proto != null && converter != null,
          'Expected proto and converter to be non-null');

      // TODO(b-136090445): Remove the cache when `getField` is no longer called
      //  during Query ordering.
      _fieldValueCache ??= <FieldPath, FieldValue>{};
      FieldValue fieldValue = _fieldValueCache[path];
      if (fieldValue == null) {
        // Instead of deserializing the full Document proto, we only deserialize
        // the value at the requested field path. This speeds up Query execution
        // as query filters can discard documents based on a single field.
        Value protoValue = proto.fields[path.getFirstSegment()];
        for (int i = 1; protoValue != null && i < path.length; ++i) {
          if (protoValue.whichValueType() != Value_ValueType.mapValue) {
            return null;
          }
          protoValue = protoValue.mapValue.fields[path.getSegment(i)];
        }

        if (protoValue != null) {
          fieldValue = converter(protoValue);
          _fieldValueCache[path] = fieldValue;
        }
      }

      return fieldValue;
    }
  }

  Object getFieldValue(FieldPath path) {
    final FieldValue value = getField(path);
    return value?.value;
  }

  bool get hasLocalMutations {
    return documentState == DocumentState.localMutations;
  }

  bool get hasCommittedMutations {
    return documentState == DocumentState.committedMutations;
  }

  @override
  bool get hasPendingWrites => hasLocalMutations || hasCommittedMutations;

  static int keyComparator(Document left, Document right) =>
      left.key.compareTo(right.key);

  @override
  int compareTo(Document other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Document &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          key == other.key &&
          documentState == other.documentState &&
          data == other.data;

  @override
  int get hashCode {
    // Note: We deliberately decided to omit `getData()` since its computation
    // is expensive.
    return key.hashCode ^ version.hashCode ^ documentState.hashCode;
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('data', data)
          ..add('version', version)
          ..add('documentState', documentState))
        .toString();
  }
}
