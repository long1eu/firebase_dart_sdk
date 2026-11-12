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

/// Represents a regular expression type in Firestore documents.
///
/// Only databases of the Enterprise edition store this type.
class RegexValue {
  /// Creates a regular expression from its [pattern] and its [options], for
  /// example `RegexValue('^foo', 'i')`.
  const RegexValue(this.pattern, this.options);

  /// The regular expression pattern.
  final String pattern;

  /// The regular expression options.
  final String options;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegexValue &&
          pattern == other.pattern &&
          options == other.options;

  @override
  int get hashCode => Object.hash(pattern, options);

  @override
  String toString() => "RegexValue{pattern='$pattern', options='$options'}";
}
