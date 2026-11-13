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

import 'package:cloud_firestore_dart/src/firebase/firestore/lite/snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';

/// Converts between the objects of an application and the maps Firestore
/// stores, for references and queries made with `withConverter`.
///
/// Unlike the converter of the main library, [fromFirestore] has no snapshot
/// options: a Firestore Lite snapshot never holds a pending server timestamp.
abstract class FirestoreDataConverter<T> {
  /// For subclasses.
  const FirestoreDataConverter();

  /// A converter made of two functions.
  const factory FirestoreDataConverter.from({
    required T Function(QueryDocumentSnapshot<Map<String, Object?>> snapshot)
    fromFirestore,
    required Map<String, Object?> Function(T value, SetOptions? options)
    toFirestore,
  }) = _FunctionDataConverter<T>;

  /// Converts the data of [snapshot] (an existing document) to a [T].
  T fromFirestore(QueryDocumentSnapshot<Map<String, Object?>> snapshot);

  /// Converts [value] to the map to write. [options] are the options of the
  /// `set` call, null when it had none.
  Map<String, Object?> toFirestore(T value, SetOptions? options);
}

class _FunctionDataConverter<T> extends FirestoreDataConverter<T> {
  const _FunctionDataConverter({
    required T Function(QueryDocumentSnapshot<Map<String, Object?>>)
    fromFirestore,
    required Map<String, Object?> Function(T, SetOptions?) toFirestore,
  }) : _from = fromFirestore,
       _to = toFirestore;

  final T Function(QueryDocumentSnapshot<Map<String, Object?>>) _from;
  final Map<String, Object?> Function(T, SetOptions?) _to;

  @override
  T fromFirestore(QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
      _from(snapshot);

  @override
  Map<String, Object?> toFirestore(T value, SetOptions? options) =>
      _to(value, options);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FunctionDataConverter<T> &&
          _from == other._from &&
          _to == other._to;

  @override
  int get hashCode => Object.hash(_from, _to);
}

/// The map to write for [data]: [data] itself without a converter.
Map<String, Object?> toRawData<T>(
  T data,
  FirestoreDataConverter<T>? converter,
  SetOptions? options,
) {
  if (converter == null) {
    return data as Map<String, Object?>;
  }
  return converter.toFirestore(data, options);
}
