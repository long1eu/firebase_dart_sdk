/// Child-name ordering on plain strings. JS: `core/util/util.ts` (`MIN_NAME`, `MAX_NAME`,
/// `nameCompare`, `stringCompare`); Android: `snapshot/ChildKey.java` (`compareTo`).
///
/// [ChildKey] carries the parsed integer and is what nodes use; these helpers are for the places
/// that still hold strings (wire paths, query names).
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';

/// The name that sorts before every other name.
const String minName = '[MIN_NAME]';

/// The name that sorts after every other name.
const String maxName = '[MAX_NAME]';

/// Compares two child names: [minName] first, [maxName] last, integer-like names numerically
/// before all other names, the rest by UTF-16 code units.
///
/// Equal integers (`1` and `01`) order by length, shorter first.
int nameCompare(String a, String b) {
  if (a == b) {
    return 0;
  } else if (a == minName || b == maxName) {
    return -1;
  } else if (b == minName || a == maxName) {
    return 1;
  }
  final int? aInt = tryParseIntKey(a);
  final int? bInt = tryParseIntKey(b);
  if (aInt != null) {
    if (bInt == null) {
      return -1;
    }
    final int diff = aInt - bInt;
    return diff == 0 ? a.length - b.length : diff;
  } else if (bInt != null) {
    return 1;
  }
  return a.compareTo(b);
}

/// Compares two strings by UTF-16 code units (JS `<`), returning -1, 0 or 1.
int stringCompare(String a, String b) => a.compareTo(b).sign;
