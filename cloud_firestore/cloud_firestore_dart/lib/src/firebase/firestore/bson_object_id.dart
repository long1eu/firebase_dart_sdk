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

/// Represents a BSON ObjectId type in Firestore documents.
///
/// Only databases of the Enterprise edition store this type.
class BsonObjectId {
  /// Creates an ObjectId from its 24-character hex string representation.
  const BsonObjectId(this.value);

  /// The 24-character hex string representation of the ObjectId.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BsonObjectId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => "BsonObjectId{value='$value'}";
}
