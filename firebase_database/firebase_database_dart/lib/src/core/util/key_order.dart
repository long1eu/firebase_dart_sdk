/// Child-name ordering on plain strings. JS: `core/util/util.ts` (`MIN_NAME`, `MAX_NAME`,
/// `nameCompare`, `stringCompare`); Android: `snapshot/ChildKey.java` (`compareTo`).
///
/// [ChildKey] carries the parsed integer and is what nodes use; these helpers are for the places
/// that still hold strings (wire paths, query names).
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';

/// The name that sorts before every other name.
const String minName = '[MIN_NAME]';

/// The name that sorts after every other name.
const String maxName = '[MAX_NAME]';

/// Compares two child names: [minName] first, [maxName] last, integer-like names numerically
/// before all other names, the rest by UTF-16 code units.
int nameCompare(String a, String b) => throw UnimplementedError();

/// Compares two strings by UTF-16 code units (JS `<`), returning -1, 0 or 1.
int stringCompare(String a, String b) => throw UnimplementedError();
