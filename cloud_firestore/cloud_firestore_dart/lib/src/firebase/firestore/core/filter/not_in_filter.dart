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

part of filter;

/// A Filter that implements the not-in operator.
class NotInFilter extends FieldFilter {
  NotInFilter(FieldPath field, FieldValue value)
      : super._(field, FilterOperator.NOT_IN, value) {
    hardAssert(value is ArrayValue, 'NotInFilter expects an ArrayValue');
  }

  @override
  bool matches(Document doc) {
    final ArrayValue arrayValue = value as ArrayValue;
    // A not-in filter that lists null can never match anything.
    if (arrayValue.internalValue.contains(NullValue.nullValue())) {
      return false;
    }
    // Documents where the field is missing or null are excluded.
    final FieldValue? other = doc.getField(field);
    return other != null &&
        other is! NullValue &&
        !arrayValue.internalValue.contains(other);
  }
}
