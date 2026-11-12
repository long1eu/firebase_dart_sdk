// Additional helpers for the core/remote unit tests.
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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';

import 'test_util.dart';

/// Creates a [Bound] from the given raw values. [inclusive] is true for
/// `startAt` / `endAt` and false for `startAfter` / `endBefore`.
Bound bound(bool inclusive, [List<Object?> values = const <Object?>[]]) {
  return Bound(
    position: values.map<FieldValue>(wrap).toList(),
    inclusive: inclusive,
  );
}
