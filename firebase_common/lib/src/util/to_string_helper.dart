// Copyright (c) 2015, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

int _indentingBuiltValueToStringHelperIndent = 0;

class ToStringHelper {
  StringBuffer _result = StringBuffer();

  ToStringHelper(Type className) {
    _result..write(className.toString())..write(' {\n');
    _indentingBuiltValueToStringHelperIndent += 2;
  }

  void add(String field, Object value) {
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
    _result..write(' ' * _indentingBuiltValueToStringHelperIndent)..write('}');
    final String stringResult = _result.toString();
    _result = null;
    return stringResult;
  }
}
