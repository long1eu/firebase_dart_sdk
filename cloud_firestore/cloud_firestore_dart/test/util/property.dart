// A tiny seeded property-testing kit (no dependency).
//
//  * [Gen] is a deterministic random source with generators for Firestore
//    values, documents, queries and writes. It does not use `dart:math`, so a
//    seed produces the same case on every Dart version and platform.
//  * [forAll] / [forAllAsync] run a property over many generated cases. A
//    failure reports the seed of the failing case and a smaller failing case
//    found by generating the same seed again with a smaller size.
//
// Environment:
//   PROPERTY_SEED   first case seed (default: a fixed seed, so runs are
//                   reproducible). A failure prints the value to use here.
//   PROPERTY_SCALE  multiplies the number of cases (default 1).
//   PROPERTY_TRACE  1 prints every backend query before it runs, to find one
//                   that hangs.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

/// The default first seed; any fixed number would do.
const int defaultSeed = 20261113;

int get _scale => int.parse(Platform.environment['PROPERTY_SCALE'] ?? '1');

int get baseSeed =>
    int.parse(Platform.environment['PROPERTY_SEED'] ?? '$defaultSeed');

/// Whether to print every case before it runs (`PROPERTY_TRACE=1`), to find
/// a case that hangs.
bool get traceProperties => Platform.environment['PROPERTY_TRACE'] == '1';

/// The number of cases to run for a property that runs [base] cases by default.
int cases(int base) => base * _scale;

/// The seed of case [index].
int caseSeed(int index) => (baseSeed + index * 7919) & 0x7fffffff;

/// The default size of generated cases (depth and breadth of values, number
/// of filters, ...). Shrinking regenerates a case with smaller sizes.
const int defaultSize = 6;

/// A deterministic random source (xorshift32) with Firestore generators.
class Gen {
  Gen(this.seed, {this.size = defaultSize})
      : _state = (seed * 2654435761 + 0x9e3779b9) & 0xffffffff {
    if (_state == 0) {
      _state = 0x1234567;
    }
    // Decorrelate neighbouring seeds.
    for (int i = 0; i < 8; i++) {
      _next();
    }
  }

  final int seed;
  final int size;
  int _state;

  int _next() {
    int x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    return _state = x & 0xffffffff;
  }

  /// An integer in `[0, max)`.
  int below(int max) => max <= 1 ? 0 : _next() % max;

  /// An integer in `[min, max]`.
  int between(int min, int max) => min + below(max - min + 1);

  bool chance(int percent) => below(100) < percent;

  T pick<T>(List<T> options) => options[below(options.length)];

  /// A uniformly random 64-bit pattern.
  int bits64() => (_next() << 32) | _next();

  // --------------------------------------------------------------- scalars

  static const List<int> _interestingInts = <int>[
    0, 1, -1, 2, -2, 255, 256, 65535, 65536, 2147483647, -2147483648, //
    2147483648, 4294967296, 9007199254740992, 9007199254740993,
    -9007199254740993, 9223372036854775807, -9223372036854775808,
    9223372036854775806, 1000000, -1000000,
  ];

  int integer() {
    switch (below(4)) {
      case 0:
        return pick(_interestingInts);
      case 1:
        return between(-20, 20);
      case 2:
        return bits64();
      default:
        // Any magnitude.
        return bits64() >> below(64);
    }
  }

  static const List<double> _interestingDoubles = <double>[
    0.0, -0.0, 1.0, -1.0, 0.5, 1.5, -2.5, double.nan, double.infinity, //
    double.negativeInfinity, double.minPositive, double.maxFinite,
    -double.maxFinite, 9007199254740992.0, 9007199254740994.0,
    9223372036854775807.0, -9223372036854775808.0, 1e-7, 1e21, 2147483648.0,
    0.1, 0.30000000000000004,
  ];

  double float() {
    switch (below(4)) {
      case 0:
        return pick(_interestingDoubles);
      case 1:
        return between(-20, 20).toDouble();
      case 2:
        // Any bit pattern except NaNs with a payload (they are all NaN).
        final double d = ByteData(8)
            .let((ByteData b) => b..setInt64(0, bits64()))
            .getFloat64(0);
        return d.isNaN ? double.nan : d;
      default:
        return between(-1000000, 1000000) / 1000.0;
    }
  }

  static const List<String> _stringParts = <String>[
    '', 'a', 'b', 'A', 'aa', 'ab', 'z', '0', ' ', '_', '.', '/', '`', '\\', //
    '\u0000', '\u0001', '\u007f', '\u0080', 'é', 'ü', 'ÿ', '߿', 'ࠀ',
    '中', '퟿', '', '￿', '😀', '𐀀', '\u{10ffff}', 'é',
    'İ', 'ß', '~', '*', '[', ']', '__', '\n', '"', "'",
  ];

  String string() {
    final int parts = below(size + 1);
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < parts; i++) {
      buffer.write(pick(_stringParts));
    }
    return buffer.toString();
  }

  /// A short field name that needs no escaping and is not reserved.
  String fieldName() => pick(const <String>['a', 'b', 'c', 'd', 'e']);

  /// A map key: mostly plain names, sometimes one that needs escaping.
  String mapKey() {
    if (chance(80)) {
      return fieldName();
    }
    final String key = pick(const <String>[
      'k.dot', 'k space', 'k`tick', 'k/slash', 'kü', 'k😀', '0', 'k~', 'k*', //
      'k[', 'K', 'a.b',
    ]);
    return key;
  }

  Uint8List bytes() {
    final int length = below(size + 2);
    return Uint8List.fromList(
        <int>[for (int i = 0; i < length; i++) pick(_interestingBytes)]);
  }

  static const List<int> _interestingBytes = <int>[0, 1, 2, 127, 128, 254, 255];

  Timestamp timestamp() {
    // 0001-01-01 .. 9999-12-31, microsecond precision (what the backend keeps).
    const int min = -62135596800;
    const int max = 253402300799;
    final int seconds;
    switch (below(4)) {
      case 0:
        seconds = pick(const <int>[min, max, 0, -1, 1, 1700000000]);
        break;
      case 1:
        seconds = between(-5, 5);
        break;
      default:
        seconds = min + (bits64() & 0x7fffffffffff) % (max - min + 1);
    }
    final int micros =
        chance(50) ? pick(const <int>[0, 1, 999999, 500000]) : below(1000000);
    return Timestamp(seconds, micros * 1000);
  }

  GeoPoint geoPoint() {
    double coordinate(double limit) => chance(30)
        ? pick(<double>[-limit, limit, 0.0, -0.0])
        : between(-(limit * 1000).toInt(), (limit * 1000).toInt()) / 1000.0;
    return GeoPoint(coordinate(90), coordinate(180));
  }

  VectorValue vector() => VectorValue(<double>[
        for (int i = between(1, size.clamp(1, 4)); i > 0; i--)
          chance(30) ? float() : between(-3, 3).toDouble()
      ].map((double d) => d.isNaN || d.isInfinite ? 0.5 : d).toList());

  // ------------------------------------------------------------------ BSON

  Object bsonScalar() {
    switch (below(7)) {
      case 0:
        return MinKey.instance;
      case 1:
        return MaxKey.instance;
      case 2:
        return Int32Value(chance(40)
            ? pick(const <int>[0, 1, -1, 2147483647, -2147483648])
            : between(-50, 50));
      case 3:
        return Decimal128Value(pick(const <String>[
          '0', '-0', '1', '-1', '1.0', '1.5', '2.5', '-2.5', '1e3', '1E-3', //
          '0.1', '9007199254740993', '9223372036854775808',
          '-9223372036854775809', '1.000000000000000000000000000000001',
          'NaN', 'Infinity', '-Infinity', '3', '20', '1e6144', '1e-6176',
        ]));
      case 4:
        return BsonObjectId(<String>[
          for (int i = 0; i < 24; i++)
            pick(const <String>['0', '1', '7', '8', 'a', 'f'])
        ].join());
      case 5:
        return BsonTimestamp(
            chance(50) ? pick(const <int>[0, 1, 4294967295]) : below(1000),
            chance(50) ? pick(const <int>[0, 1, 4294967295]) : below(1000));
      default:
        return chance(50)
            ? RegexValue(pick(const <String>['', '^a', 'a.*', 'b', 'é']),
                pick(const <String>['', 'i', 'im', 'x']))
            : Blob.bsonBinary(pick(const <int>[0, 1, 2, 128, 255]), bytes());
    }
  }

  // ----------------------------------------------------------- value trees

  /// The paths of generated document references. Tests that cannot handle
  /// references of different depths replace it.
  List<String> referencePaths = const <String>[
    'c/a', 'c/b', 'c/aa', 'd/a', 'c/a/s/a', 'c/A', 'c/é', 'c/0', 'c/10', //
    'c/9',
  ];

  /// A value as a user would pass it to the SDK.
  ///
  /// [reference] creates a document reference for a path such as `c/d`; no
  /// references are generated without it. [depth] bounds the nesting.
  Object? value({
    bool bson = false,
    Object Function(String path)? reference,
    bool vectors = true,
    int? depth,
    bool insideArray = false,
  }) {
    final int remaining = depth ?? (size ~/ 2).clamp(0, 3);
    final int kinds = remaining > 0 ? 13 : 11;
    for (;;) {
      switch (below(kinds + (bson ? 3 : 0))) {
        case 0:
          return null;
        case 1:
          return chance(50);
        case 2:
          return integer();
        case 3:
          return float();
        case 4:
          return string();
        case 5:
          return timestamp();
        case 6:
          return geoPoint();
        case 7:
          return Blob(bytes());
        case 8:
          if (reference == null) {
            continue;
          }
          return reference(pick(referencePaths));
        case 9:
          if (!vectors || insideArray) {
            continue;
          }
          return vector();
        case 10:
          return integer();
        case 11:
          if (insideArray) {
            continue;
          }
          return <Object?>[
            for (int i = below(size.clamp(0, 4) + 1); i > 0; i--)
              value(
                  bson: bson,
                  reference: reference,
                  vectors: vectors,
                  depth: remaining - 1,
                  insideArray: true)
          ];
        case 12:
          return map(
              bson: bson,
              reference: reference,
              vectors: vectors,
              depth: remaining - 1);
        default:
          return bsonScalar();
      }
    }
  }

  /// A map value (also the data of a document).
  Map<String, Object?> map({
    bool bson = false,
    Object Function(String path)? reference,
    bool vectors = true,
    int? depth,
    bool plainKeys = false,
  }) {
    final Map<String, Object?> result = <String, Object?>{};
    for (int i = below(size.clamp(0, 5) + 1); i > 0; i--) {
      result[plainKeys ? fieldName() : mapKey()] = value(
          bson: bson, reference: reference, vectors: vectors, depth: depth);
    }
    return result;
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T it) block) => block(this);
}

/// A readable form of a generated value, for failure messages.
String describe(Object? value) {
  if (value is double) {
    if (value == 0 && value.isNegative) {
      return '-0.0';
    }
    return value.toString();
  } else if (value is String) {
    return jsonEncode(value) +
        (value.runes.any((int r) => r > 126 || r < 32)
            ? ' (U+${value.runes.map((int r) => r.toRadixString(16)).join(' U+')})'
            : '');
  } else if (value is List) {
    return '[${value.map(describe).join(', ')}]';
  } else if (value is Map) {
    return '{${value.entries.map((MapEntry<Object?, Object?> e) => '${describe(e.key)}: ${describe(e.value)}').join(', ')}}';
  } else if (value is Blob) {
    return 'Blob(${value.subtype == 0 ? '' : 'subtype ${value.subtype}, '}${value.bytes})';
  } else if (value is DocumentReference) {
    return 'ref(${value.path})';
  } else if (value is int) {
    return '${value}i';
  }
  return value.toString();
}

String _failure(String name, int seed, int size, Object error,
    StackTrace stackTrace, String? description) {
  return 'Property "$name" failed.\n'
      '  seed: $seed, size: $size '
      '(rerun this case first with PROPERTY_SEED=$seed)\n'
      '${description == null ? '' : '  case: ${description.length > 1500 ? '${description.substring(0, 1500)}... (${description.length} characters)' : description}\n'}'
      '  error: ${error.toString().replaceAll('\n', '\n    ')}\n'
      '  at: ${stackTrace.toString().split('\n').take(6).join('\n      ')}';
}

/// Runs [check] on [count] cases produced by [generate]. On a failure the
/// case is generated again from the same seed with smaller sizes, and the
/// smallest size that still fails is reported with its seed.
void forAll<T>(
  String name, {
  required int count,
  required T Function(Gen gen) generate,
  required void Function(T value) check,
  String Function(T value)? show,
}) {
  for (int i = 0; i < count; i++) {
    final int seed = caseSeed(i);
    try {
      check(generate(Gen(seed)));
    } catch (_) {
      for (int size = 0; size <= defaultSize; size++) {
        late T value;
        try {
          value = generate(Gen(seed, size: size));
          check(value);
        } catch (error, stackTrace) {
          String? description;
          try {
            description = (show ?? (T v) => describe(v))(value);
          } catch (_) {
            // The generator itself failed.
          }
          fail(_failure(name, seed, size, error, stackTrace, description));
        }
      }
      rethrow;
    }
  }
}

/// [forAll] for asynchronous checks.
Future<void> forAllAsync<T>(
  String name, {
  required int count,
  required T Function(Gen gen) generate,
  required Future<void> Function(T value) check,
  String Function(T value)? show,
}) async {
  for (int i = 0; i < count; i++) {
    final int seed = caseSeed(i);
    try {
      await check(generate(Gen(seed)));
    } catch (_) {
      for (int size = 0; size <= defaultSize; size++) {
        late T value;
        try {
          value = generate(Gen(seed, size: size));
          await check(value);
        } catch (error, stackTrace) {
          String? description;
          try {
            description = (show ?? (T v) => describe(v))(value);
          } catch (_) {
            // The generator itself failed.
          }
          fail(_failure(name, seed, size, error, stackTrace, description));
        }
      }
      rethrow;
    }
  }
}

/// Removes elements of [items] while [fails] stays true and returns what is
/// left: a locally minimal failing list.
Future<List<T>> shrinkList<T>(
    List<T> items, Future<bool> Function(List<T> candidate) fails) async {
  List<T> current = List<T>.of(items);
  int chunk = current.length ~/ 2;
  while (chunk >= 1) {
    bool removed = false;
    for (int start = 0; start < current.length;) {
      final List<T> candidate = <T>[
        ...current.sublist(0, start),
        ...current.sublist((start + chunk).clamp(0, current.length)),
      ];
      if (candidate.length < current.length && await fails(candidate)) {
        current = candidate;
        removed = true;
      } else {
        start += chunk;
      }
    }
    if (!removed || chunk == 1) {
      chunk ~/= 2;
    }
  }
  return current;
}
