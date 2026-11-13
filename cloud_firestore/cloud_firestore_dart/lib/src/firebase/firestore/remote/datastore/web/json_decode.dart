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

import 'dart:convert';

/// Decodes a JSON response of the backend (REST or WebChannel) like `jsonDecode`, except that the number `-0` stays
/// the double -0.0.
///
/// Production Firestore writes the double -0.0 as `"doubleValue": -0` (checked on 2026-11-13 for a document get,
/// RunQuery and BatchGet). `jsonDecode` reads `-0` as the int 0, which has no sign, so the value came back as 0.0
/// over the web transport. In JavaScript `JSON.parse('-0')` is -0, so the JS SDK keeps it without doing anything. The
/// emulator writes `-0.0` and never showed it.
Object? decodeBackendJson(String text) {
  if (!text.contains('-0')) {
    return jsonDecode(text);
  }
  return jsonDecode(_negativeZeroAsDouble(text));
}

/// Rewrites every number token `-0` (outside strings, not followed by more of a number) as `-0.0`.
String _negativeZeroAsDouble(String text) {
  const int quote = 0x22; // "
  const int backslash = 0x5c; // \
  const int minus = 0x2d; // -
  const int zero = 0x30; // 0
  StringBuffer? out;
  int copiedUpTo = 0;
  bool inString = false;
  final int length = text.length;
  for (int i = 0; i < length; i++) {
    final int c = text.codeUnitAt(i);
    if (inString) {
      if (c == backslash) {
        i++; // The escaped character, which may be a quote.
      } else if (c == quote) {
        inString = false;
      }
      continue;
    }
    if (c == quote) {
      inString = true;
    } else if (c == minus &&
        i + 1 < length &&
        text.codeUnitAt(i + 1) == zero &&
        !_continuesNumber(text, i + 2)) {
      (out ??= StringBuffer())
        ..write(text.substring(copiedUpTo, i))
        ..write('-0.0');
      copiedUpTo = i + 2;
      i++;
    }
  }
  if (out == null) {
    return text;
  }
  return (out..write(text.substring(copiedUpTo))).toString();
}

/// Whether the character at [index] continues a number (a digit, a fraction or an exponent).
bool _continuesNumber(String text, int index) {
  if (index >= text.length) {
    return false;
  }
  final int c = text.codeUnitAt(index);
  return (c >= 0x30 && c <= 0x39) ||
      c == 0x2e ||
      c == 0x65 ||
      c == 0x45; // 0-9 . e E
}
