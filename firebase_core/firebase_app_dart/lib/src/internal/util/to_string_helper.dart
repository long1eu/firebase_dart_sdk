// Copyright (c) 2015, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

int _indentingBuiltValueToStringHelperIndent = 0;

/// Builds indented `toString` output of the form `Name { field=value, }`.
class ToStringHelper {
  /// Starts the description of an instance of [className].
  ToStringHelper(Type className) {
    _result
      ..write(className.toString())
      ..write(' {\n');
    _indentingBuiltValueToStringHelperIndent += 2;
  }

  final StringBuffer _result = StringBuffer();

  /// Adds a `field=value` line; `null` values are left out.
  void add(String field, Object? value) {
    if (value != null) {
      _result
        ..write(' ' * _indentingBuiltValueToStringHelperIndent)
        ..write(field)
        ..write('=')
        ..write(value)
        ..write(',\n');
    }
  }

  @override
  String toString() {
    _indentingBuiltValueToStringHelperIndent -= 2;
    _result
      ..write(' ' * _indentingBuiltValueToStringHelperIndent)
      ..write('}');
    final String stringResult = _result.toString();
    return stringResult;
  }
}
