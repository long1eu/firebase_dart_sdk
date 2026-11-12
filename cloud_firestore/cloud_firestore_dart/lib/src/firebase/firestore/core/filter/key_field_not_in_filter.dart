// Copyright 2020 Google LLC
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

part of 'filter.dart';

/// A Filter that implements the not-in operator on the document key.
class KeyFieldNotInFilter extends FieldFilter {
  KeyFieldNotInFilter(FieldPath field, FieldValue value)
    : super._(field, FilterOperator.NOT_IN, value) {
    hardAssert(
      value is ArrayValue,
      'KeyFieldNotInFilter expects an ArrayValue',
    );
    final ArrayValue arrayValue = value as ArrayValue;
    for (FieldValue refValue in arrayValue.internalValue) {
      hardAssert(
        refValue is ReferenceValue,
        'Comparing on key with not_in, but an array value was not a ReferenceValue',
      );
    }
  }

  @override
  bool matches(Document doc) {
    final ArrayValue arrayValue = value as ArrayValue;
    for (FieldValue refValue in arrayValue.internalValue) {
      if (doc.key == refValue.value) {
        return false;
      }
    }
    return true;
  }
}
