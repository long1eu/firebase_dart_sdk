/// Push id generation. JS: `core/util/NextPushId.ts`; Android: `core/utilities/PushIdGenerator.java`.
library;

import 'dart:math';

/// The 64 characters of push ids, in ascending ASCII order.
const String pushChars =
    '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

/// The longest key [successor] and [predecessor] produce.
const int maxKeyLength = 786;

/// Generates chronologically ordered push ids: 8 characters of time and 12 random characters;
/// within one millisecond the random part of the previous id is incremented with carry.
final class PushIdGenerator {
  /// Creates a generator reading the (server) time from [nowMillis] and randomness from [random].
  PushIdGenerator({required this.nowMillis, required this.random});

  /// The server time in milliseconds since the epoch.
  final int Function() nowMillis;

  /// The random source.
  final Random random;

  /// Returns the next push id.
  String next() => throw UnimplementedError();
}

/// The smallest key that sorts after [key] (used by `startAfter` on the key index).
String successor(String key) => throw UnimplementedError();

/// The largest key that sorts before [key] (used by `endBefore` on the key index).
String predecessor(String key) => throw UnimplementedError();
