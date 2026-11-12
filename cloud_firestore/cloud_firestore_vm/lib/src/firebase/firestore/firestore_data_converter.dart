// Copyright 2018 Google LLC
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

import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/set_options.dart';

/// Options that configure how data is retrieved from a [DocumentSnapshot], for
/// example how pending server timestamps are returned. Passed to
/// [FirestoreDataConverter.fromFirestore].
class SnapshotOptions {
  const SnapshotOptions({this.serverTimestamps = ServerTimestampBehavior.none});

  /// How a server timestamp that has not been resolved yet is returned.
  final ServerTimestampBehavior serverTimestamps;
}

/// Converts between your own model class [T] and the raw field map stored in
/// Firestore.
///
/// Attach a converter with `withConverter` on a `DocumentReference`,
/// `CollectionReference` or `Query`. Implement this class, or build one from two
/// functions (for example constructor tear-offs) with
/// [FirestoreDataConverter.from]:
///
/// ```dart
/// final FirestoreDataConverter<City> converter = FirestoreDataConverter<City>.from(
///   fromFirestore: (snapshot, options) => City.fromMap(snapshot.data!),
///   toFirestore: (city, options) => city.toMap(),
/// );
/// ```
abstract class FirestoreDataConverter<T> {
  const FirestoreDataConverter();

  /// Creates a converter from two functions. The returned converters compare
  /// equal when both functions are equal (top level functions, static methods
  /// and constructor tear-offs are canonical, so this works for them).
  const factory FirestoreDataConverter.from({
    required T Function(DocumentSnapshot<Map<String, Object?>> snapshot,
            SnapshotOptions? options)
        fromFirestore,
    required Map<String, Object?> Function(T value, SetOptions? options)
        toFirestore,
  }) = _FunctionDataConverter<T>;

  /// Called by the SDK to convert a snapshot of an existing document into
  /// [T]. [snapshot] is an untyped snapshot (at runtime a
  /// `QueryDocumentSnapshot`, so `snapshot.data` is never null). Use
  /// `snapshot.getData(options?.serverTimestamps ?? ServerTimestampBehavior.none)`
  /// to honour the requested server timestamp behavior.
  T fromFirestore(DocumentSnapshot<Map<String, Object?>> snapshot,
      SnapshotOptions? options);

  /// Called by the SDK to convert [value] into the map that is written.
  /// [options] are the [SetOptions] of the write, or null (for example for
  /// `add`).
  Map<String, Object?> toFirestore(T value, SetOptions? options);
}

class _FunctionDataConverter<T> extends FirestoreDataConverter<T> {
  const _FunctionDataConverter({
    required T Function(
            DocumentSnapshot<Map<String, Object?>>, SnapshotOptions?)
        fromFirestore,
    required Map<String, Object?> Function(T, SetOptions?) toFirestore,
  })  : _from = fromFirestore,
        _to = toFirestore;

  final T Function(DocumentSnapshot<Map<String, Object?>>, SnapshotOptions?)
      _from;
  final Map<String, Object?> Function(T, SetOptions?) _to;

  @override
  T fromFirestore(DocumentSnapshot<Map<String, Object?>> snapshot,
          SnapshotOptions? options) =>
      _from(snapshot, options);

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
