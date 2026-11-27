/// Query parameters and their wire forms. JS: `core/view/QueryParams.ts`; Android:
/// `core/view/QueryParams.java`.
///
/// The node filter for the parameters is `nodeFilterFor` in `view/filter/node_filter.dart` (JS
/// `queryParamsGetNodeFilter`), so this data-layer file does not depend on the view layer.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';

/// Which end a limit counts from.
enum ViewFrom {
  /// `limitToFirst` (wire `l`).
  left,

  /// `limitToLast` (wire `r`).
  right,
}

/// The immutable parameters of a query: index, bounds and limit. Every builder returns a copy.
///
/// Mirrors the JS fields (`startSet_`, `startNameSet_`, `startAfterSet_`, ...), so the wire object,
/// the wire object and the query identifier equal the JS SDK's.
final class QueryParams {
  QueryParams._({
    this.index = priorityIndex,
    this.hasStart = false,
    Node? startValue,
    ChildKey? startName,
    this.startInclusive = true,
    this.hasEnd = false,
    Node? endValue,
    ChildKey? endName,
    this.endInclusive = true,
    this.hasLimit = false,
    int limit = 0,
    ViewFrom? viewFrom,
  }) : _startValue = startValue,
       _startName = startName,
       _endValue = endValue,
       _endName = endName,
       _limit = limit,
       _viewFrom = viewFrom;

  static final QueryParams _default = QueryParams._();

  /// The parameters of the default query (priority index, no bounds, no limit).
  static QueryParams get defaultParams => _default;

  /// Parses the wire object (the inverse of [toWireObject]), as persisted tracked queries store it.
  factory QueryParams.fromWireObject(Map<String, Object?> wire) {
    final bool hasStart = wire.containsKey(_wireStartValue);
    final bool hasEnd = wire.containsKey(_wireEndValue);
    final Object? limit = wire[_wireLimit];
    final Object? viewFrom = wire[_wireViewFrom];
    final Object? index = wire[_wireIndex];
    final Object? startName = wire[_wireStartName];
    final Object? endName = wire[_wireEndName];
    return QueryParams._(
      index: index is String ? _indexFromQueryDefinition(index) : priorityIndex,
      hasStart: hasStart,
      startValue: hasStart ? nodeFromJson(wire[_wireStartValue]) : null,
      startName: hasStart && startName is String ? _parseName(startName) : null,
      startInclusive: wire[_wireStartInclusive] != false,
      hasEnd: hasEnd,
      endValue: hasEnd ? nodeFromJson(wire[_wireEndValue]) : null,
      endName: hasEnd && endName is String ? _parseName(endName) : null,
      endInclusive: wire[_wireEndInclusive] != false,
      hasLimit: limit is num,
      limit: limit is num ? limit.toInt() : 0,
      viewFrom: viewFrom == _viewFromLeft
          ? ViewFrom.left
          : viewFrom == _viewFromRight
          ? ViewFrom.right
          : null,
    );
  }

  /// The index.
  final Index index;

  /// Whether a start bound is set.
  final bool hasStart;

  final Node? _startValue;
  final ChildKey? _startName;

  /// The start value; only with [hasStart].
  Node get indexStartValue {
    assert(hasStart, 'Only valid if start has been set');
    return _startValue!;
  }

  /// The start key: the given key, or [ChildKey.min] (or [ChildKey.max] for `startAfter` without
  /// a key); only with [hasStart].
  ChildKey get indexStartName {
    assert(hasStart, 'Only valid if start has been set');
    return _startName ?? ChildKey.min;
  }

  /// Whether the start bound is inclusive (false after `startAfter`).
  final bool startInclusive;

  /// Whether an end bound is set.
  final bool hasEnd;

  final Node? _endValue;
  final ChildKey? _endName;

  /// The end value; only with [hasEnd].
  Node get indexEndValue {
    assert(hasEnd, 'Only valid if end has been set');
    return _endValue!;
  }

  /// The end key; only with [hasEnd].
  ChildKey get indexEndName {
    assert(hasEnd, 'Only valid if end has been set');
    return _endName ?? ChildKey.max;
  }

  /// Whether the end bound is inclusive (false after `endBefore`).
  final bool endInclusive;

  /// Whether a limit is set.
  final bool hasLimit;

  final int _limit;
  final ViewFrom? _viewFrom;

  /// Whether a limit with an explicit side is set.
  bool get hasAnchoredLimit => hasLimit && _viewFrom != null;

  /// The limit; only with [hasLimit].
  int get limit {
    assert(hasLimit, 'Only valid if limit has been set');
    return _limit;
  }

  /// Whether the view is anchored at the start.
  ///
  /// Without an explicit side (legacy `limit()`), anchored at the start when a start is set.
  bool get isViewFromLeft =>
      _viewFrom == null ? hasStart : _viewFrom == ViewFrom.left;

  /// Whether the query loads all data (no bounds, no limit).
  bool get loadsAllData => !(hasStart || hasEnd || hasLimit);

  /// Whether this is the default query (also the priority index).
  bool get isDefault => loadsAllData && index == priorityIndex;

  /// Whether the parameters are consistent.
  bool get isValid => !(hasStart && hasEnd && hasLimit && !hasAnchoredLimit);

  QueryParams _copy({
    Index? index,
    bool? hasStart,
    Node? startValue,
    ChildKey? startName,
    bool clearStartName = false,
    bool? startInclusive,
    bool? hasEnd,
    Node? endValue,
    ChildKey? endName,
    bool clearEndName = false,
    bool? endInclusive,
    bool? hasLimit,
    int? limit,
    ViewFrom? viewFrom,
  }) => QueryParams._(
    index: index ?? this.index,
    hasStart: hasStart ?? this.hasStart,
    startValue: startValue ?? _startValue,
    startName: clearStartName ? null : (startName ?? _startName),
    startInclusive: startInclusive ?? this.startInclusive,
    hasEnd: hasEnd ?? this.hasEnd,
    endValue: endValue ?? _endValue,
    endName: clearEndName ? null : (endName ?? _endName),
    endInclusive: endInclusive ?? this.endInclusive,
    hasLimit: hasLimit ?? this.hasLimit,
    limit: limit ?? _limit,
    viewFrom: viewFrom ?? _viewFrom,
  );

  /// With `limitToFirst(limit)`.
  QueryParams limitToFirst(int limit) =>
      _copy(hasLimit: true, limit: limit, viewFrom: ViewFrom.left);

  /// With `limitToLast(limit)`.
  QueryParams limitToLast(int limit) =>
      _copy(hasLimit: true, limit: limit, viewFrom: ViewFrom.right);

  /// With an inclusive start bound.
  QueryParams startAt(Node indexValue, [ChildKey? key]) => _copy(
    hasStart: true,
    startValue: indexValue,
    startName: key,
    clearStartName: key == null,
    startInclusive: true,
  );

  /// With an exclusive start bound.
  ///
  /// As JS: on any index but the key index, a missing [key] becomes [ChildKey.max], so the wire
  /// object carries `sn` with `sin: false` (the server ignores `sin` without a start name).
  QueryParams startAfter(Node indexValue, [ChildKey? key]) => _copy(
    hasStart: true,
    startValue: indexValue,
    startName: key ?? (index == keyIndex ? null : ChildKey.max),
    clearStartName: key == null && index == keyIndex,
    startInclusive: false,
  );

  /// With an inclusive end bound.
  QueryParams endAt(Node indexValue, [ChildKey? key]) => _copy(
    hasEnd: true,
    endValue: indexValue,
    endName: key,
    clearEndName: key == null,
    endInclusive: true,
  );

  /// With an exclusive end bound.
  ///
  /// As JS: on any index but the key index, a missing [key] becomes [ChildKey.min].
  QueryParams endBefore(Node indexValue, [ChildKey? key]) => _copy(
    hasEnd: true,
    endValue: indexValue,
    endName: key ?? (index == keyIndex ? null : ChildKey.min),
    clearEndName: key == null && index == keyIndex,
    endInclusive: false,
  );

  /// Ordered by [index].
  QueryParams orderBy(Index index) => _copy(index: index);

  /// The wire object (`sp`, `sn`, `sin`, `ep`, `en`, `ein`, `l`, `vf`, `i`), equal to the JS SDK's.
  Map<String, Object?> toWireObject() {
    final Map<String, Object?> obj = <String, Object?>{};
    if (hasStart) {
      obj[_wireStartValue] = _boundJson(_startValue!);
      final ChildKey? startName = _startName;
      if (startName != null) {
        obj[_wireStartName] = startName.name;
      }
      obj[_wireStartInclusive] = startInclusive;
    }
    if (hasEnd) {
      obj[_wireEndValue] = _boundJson(_endValue!);
      final ChildKey? endName = _endName;
      if (endName != null) {
        obj[_wireEndName] = endName.name;
      }
      obj[_wireEndInclusive] = endInclusive;
    }
    if (hasLimit) {
      obj[_wireLimit] = _limit;
      obj[_wireViewFrom] = isViewFromLeft ? _viewFromLeft : _viewFromRight;
    }
    // The priority index is the default, so only other indexes are sent.
    if (index != priorityIndex) {
      obj[_wireIndex] = index.queryDefinition;
    }
    return obj;
  }

  /// The query identifier: `default`, or the canonical JSON of [toWireObject] (JS
  /// `ObjectToUniqueKey`).
  String toQueryIdentifier() => _identifier;

  late final String _identifier = () {
    final String id = objectToUniqueKey(toWireObject());
    return id == '{}' ? 'default' : id;
  }();

  /// Two parameters are equal when their query identifiers are (JS `Query.isEqual`).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryParams && other._identifier == _identifier;

  @override
  int get hashCode => _identifier.hashCode;

  @override
  String toString() => _identifier;
}

const String _wireStartValue = 'sp';
const String _wireStartName = 'sn';
const String _wireStartInclusive = 'sin';
const String _wireEndValue = 'ep';
const String _wireEndName = 'en';
const String _wireEndInclusive = 'ein';
const String _wireLimit = 'l';
const String _wireViewFrom = 'vf';
const String _viewFromLeft = 'l';
const String _viewFromRight = 'r';
const String _wireIndex = 'i';

/// The JSON of a query bound; integral doubles within plus or minus 2^53 become ints, so `1.0`
/// and `1` give the same wire object and identifier on the VM and the web.
Object? _boundJson(Node value) {
  final Object? json = value.toJson();
  return json is num ? normalizeNumber(json) : json;
}

ChildKey _parseName(String name) => switch (name) {
  '[MIN_NAME]' => ChildKey.min,
  '[MAX_NAME]' => ChildKey.max,
  _ => ChildKey(name),
};

Index _indexFromQueryDefinition(String definition) => switch (definition) {
  '.priority' => priorityIndex,
  '.value' => valueIndex,
  '.key' => keyIndex,
  _ => PathIndex(Path(definition)),
};

/// JS `ObjectToUniqueKey`: `JSON.stringify` for scalars; objects with their keys sorted (UTF-16
/// code units), recursively, no spaces.
String objectToUniqueKey(Object? obj) {
  if (obj is! Map) {
    return jsStringify(obj);
  }
  final List<String> keys = obj.keys.cast<String>().toList()..sort();
  final StringBuffer key = StringBuffer('{');
  for (int i = 0; i < keys.length; i++) {
    if (i != 0) {
      key.write(',');
    }
    key
      ..write(jsStringify(keys[i]))
      ..write(':')
      ..write(objectToUniqueKey(obj[keys[i]]));
  }
  key.write('}');
  return key.toString();
}

/// JS `JSON.stringify` of decoded JSON, byte for byte (numbers as JS prints them, string escapes
/// as ES2019 well-formed `JSON.stringify`).
String jsStringify(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool) {
    return '$value';
  }
  if (value is num) {
    return _jsNumber(value);
  }
  if (value is String) {
    return _jsString(value);
  }
  if (value is List) {
    return '[${value.map(jsStringify).join(',')}]';
  }
  if (value is Map) {
    return '{${value.entries.map((MapEntry<Object?, Object?> e) => '${_jsString('${e.key}')}:${jsStringify(e.value)}').join(',')}}';
  }
  throw ArgumentError.value(value, 'value', 'Not JSON');
}

String _jsNumber(num value) {
  // On the web every number is a double and `is int` holds for -0.0, so zero
  // and the non-finite values are handled before any type test.
  if (value == 0) {
    return '0';
  }
  if (value.isNaN || value.isInfinite) {
    return 'null';
  }
  if (value is int) {
    return value.toString();
  }
  final double d = value as double;
  if (d == d.truncateToDouble() && d.abs() < 1e21) {
    // JavaScript prints the shortest digits that read back as the same double, padded with zeros
    // (123456789012345680000), not the exact binary value. Dart prints the same digits and adds
    // `.0` off the web.
    final String text = d.toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
  return d.toString();
}

String _jsString(String value) {
  final StringBuffer out = StringBuffer('"');
  final int length = value.length;
  for (int i = 0; i < length; i++) {
    final int c = value.codeUnitAt(i);
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0C:
        out.write(r'\f');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (c < 0x20) {
          out.write(_unicodeEscape(c));
        } else if (c >= 0xD800 && c <= 0xDBFF) {
          final bool paired =
              i + 1 < length &&
              value.codeUnitAt(i + 1) >= 0xDC00 &&
              value.codeUnitAt(i + 1) <= 0xDFFF;
          if (paired) {
            out
              ..writeCharCode(c)
              ..writeCharCode(value.codeUnitAt(i + 1));
            i++;
          } else {
            out.write(_unicodeEscape(c));
          }
        } else if (c >= 0xDC00 && c <= 0xDFFF) {
          out.write(_unicodeEscape(c));
        } else {
          out.writeCharCode(c);
        }
    }
  }
  out.write('"');
  return out.toString();
}

String _unicodeEscape(int c) => '\\u${c.toRadixString(16).padLeft(4, '0')}';
