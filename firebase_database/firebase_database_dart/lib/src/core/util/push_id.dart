/// Push id generation. JS: `core/util/NextPushId.ts`; Android: `core/utilities/PushIdGenerator.java`.
library;

import 'dart:math';

import 'package:firebase_database_dart/src/core/util/key_order.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';

/// The 64 characters of push ids, in ascending ASCII order.
const String pushChars =
    '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

/// The longest key [successor] and [predecessor] produce.
const int maxKeyLength = 786;

const String _minPushChar = '-';
const String _maxPushChar = 'z';

/// Generates chronologically ordered push ids: 8 characters of time and 12 random characters;
/// within one millisecond the random part of the previous id is incremented with carry.
final class PushIdGenerator {
  /// Creates a generator reading the (server) time from [nowMillis] and randomness from [random].
  PushIdGenerator({required this.nowMillis, required this.random});

  /// The server time in milliseconds since the epoch.
  final int Function() nowMillis;

  /// The random source.
  final Random random;

  int? _lastPushTime;
  final List<int> _lastRandChars = List<int>.filled(12, 0);

  /// Returns the next push id.
  ///
  /// Throws [StateError] when the time does not fit in 8 characters (48 bits).
  String next() {
    int now = nowMillis();
    final bool duplicateTime = now == _lastPushTime;
    _lastPushTime = now;

    final List<int> units = List<int>.filled(20, 0);
    for (int i = 7; i >= 0; i--) {
      units[i] = pushChars.codeUnitAt(now % 64);
      now = now ~/ 64;
    }
    if (now != 0) {
      throw StateError('Cannot generate a push id for this time.');
    }

    if (!duplicateTime) {
      for (int i = 0; i < 12; i++) {
        _lastRandChars[i] = random.nextInt(64);
      }
    } else {
      // Same millisecond: the previous random part plus one.
      int i = 11;
      for (; i >= 0 && _lastRandChars[i] == 63; i--) {
        _lastRandChars[i] = 0;
      }
      if (i >= 0) {
        _lastRandChars[i]++;
      }
    }
    for (int i = 0; i < 12; i++) {
      units[8 + i] = pushChars.codeUnitAt(_lastRandChars[i]);
    }
    return String.fromCharCodes(units);
  }
}

/// The push character after [char], or `-` when [char] is not a push character (JS `charAt`).
String _pushCharAfter(String char) => pushChars[pushChars.indexOf(char) + 1];

/// The push character before [char], or the empty string when there is none (JS `charAt`).
String _pushCharBefore(String char) {
  final int index = pushChars.indexOf(char) - 1;
  return index < 0 ? '' : pushChars[index];
}

/// The smallest key that sorts after [key] (used by `startAfter` on the key index).
String successor(String key) {
  if (key == '$int32Max') {
    // Integer keys sort before all other keys.
    return _minPushChar;
  }
  final int? keyAsInt = tryParseIntKey(key);
  if (keyAsInt != null) {
    return '${keyAsInt + 1}';
  }
  if (key.length < maxKeyLength) {
    return '$key$_minPushChar';
  }
  int i = key.length - 1;
  while (i >= 0 && key[i] == _maxPushChar) {
    i--;
  }
  // The largest possible key: MAX_NAME sorts after every key.
  if (i == -1) {
    return maxName;
  }
  return '${key.substring(0, i)}${_pushCharAfter(key[i])}';
}

/// The largest key that sorts before [key] (used by `endBefore` on the key index).
///
/// [key] must be non-empty.
String predecessor(String key) {
  if (key == '$int32Min') {
    return minName;
  }
  final int? keyAsInt = tryParseIntKey(key);
  if (keyAsInt != null) {
    return '${keyAsInt - 1}';
  }
  final int last = key.length - 1;
  if (key[last] == _minPushChar) {
    if (key.length == 1) {
      // Integer keys sort before all other keys.
      return '$int32Max';
    }
    return key.substring(0, last);
  }
  // The last character replaced by its predecessor, then filled with the largest character.
  final String head = key.substring(0, last) + _pushCharBefore(key[last]);
  final int fill = maxKeyLength - key.length;
  return head + _maxPushChar * (fill < 0 ? 0 : fill);
}
