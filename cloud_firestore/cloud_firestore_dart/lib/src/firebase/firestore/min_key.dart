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

/// Represents the Firestore "Min Key" data type, a value that sorts before
/// every other value except null.
///
/// Only databases of the Enterprise edition store this type.
class MinKey {
  const MinKey._();

  /// The only instance of [MinKey].
  static const MinKey instance = MinKey._();

  @override
  String toString() => 'MinKey';
}
