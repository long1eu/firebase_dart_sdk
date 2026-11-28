import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_remote_config_dart/src/bounded.dart';
import 'package:firebase_remote_config_dart/src/json_guard.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:meta/meta.dart';

/// Where a [RemoteConfigValue] comes from.
enum ValueSource {
  /// Neither the active template nor the defaults have the key: the text is empty.
  valueStatic,

  /// The defaults given to the constructor.
  valueDefault,

  /// The active template, fetched from the server.
  valueRemote,
}

/// A Remote Config value: its [text] and its [source].
///
/// The conversions follow the Android SDK: [asBool] knows `1`, `true`, `t`, `yes`, `y`, `on` and `0`,
/// `false`, `f`, `no`, `n`, `off` (any case, around whitespace) and the empty text; [asInt] reads a
/// decimal integer; [asDouble] a finite number. Each returns null when the text is something else, or
/// when the source is [ValueSource.valueStatic].
@immutable
final class RemoteConfigValue {
  /// Creates a value with [text] from [source].
  const RemoteConfigValue(this.text, this.source);

  /// The text of the value, as the server or the defaults gave it.
  final String text;

  /// Where the value comes from.
  final ValueSource source;

  /// The [text].
  String asString() => text;

  /// The UTF-8 bytes of [text] (Android's `getByteArray`); empty for a static value.
  Uint8List asBytes() => utf8.encode(text);

  /// The JSON value [text] holds (iOS's `jsonValue`), as `jsonDecode` gives it: a
  /// `Map<String, dynamic>`, `List<dynamic>`, `String`, `num`, `bool` or null.
  ///
  /// Returns null when the text is not JSON, nests arrays and objects deeper than 32 levels, is over
  /// 16 MiB of UTF-8, or the source is [ValueSource.valueStatic]; a text of `null` also gives null.
  /// Never throws.
  Object? asJson() {
    if (source == ValueSource.valueStatic ||
        utf8Length(text, stopAfter: maxRecordBytes) > maxRecordBytes) {
      return null;
    }
    try {
      return decodeGuardedText(text);
    } on FormatException {
      return null;
    }
  }

  /// The value as a boolean, or null when the text is not one of the known words or the source is
  /// [ValueSource.valueStatic].
  bool? asBool() {
    if (source == ValueSource.valueStatic) {
      return null;
    }
    final String word = text.trim().toLowerCase();
    if (_trueWords.contains(word)) {
      return true;
    }
    if (word.isEmpty || _falseWords.contains(word)) {
      return false;
    }
    return null;
  }

  /// The value as an integer, or null when the text is not a decimal integer (an optional sign, then
  /// digits, around whitespace) within 64 bits on the VM and within ±(2^53 − 1) on the web, or the
  /// source is [ValueSource.valueStatic].
  int? asInt() {
    if (source == ValueSource.valueStatic) {
      return null;
    }
    final String trimmed = text.trim();
    if (!_integer.hasMatch(trimmed)) {
      return null;
    }
    final int? parsed = int.tryParse(trimmed);
    if (parsed == null) {
      return null;
    }
    if (_isWeb && (parsed > maxSafeInteger || parsed < -maxSafeInteger)) {
      return null;
    }
    return parsed;
  }

  /// The value as a finite double, or null when the text is not a number, is not finite, or the source
  /// is [ValueSource.valueStatic].
  double? asDouble() {
    if (source == ValueSource.valueStatic) {
      return null;
    }
    final double? parsed = double.tryParse(text.trim());
    if (parsed == null || !parsed.isFinite) {
      return null;
    }
    return parsed;
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteConfigValue &&
      other.text == text &&
      other.source == source;

  @override
  int get hashCode => Object.hash(text, source);

  @override
  String toString() => 'RemoteConfigValue(${source.name}, "$text")';
}

/// The value of a key that is neither active nor a default.
const RemoteConfigValue staticValue = RemoteConfigValue(
  '',
  ValueSource.valueStatic,
);

const Set<String> _trueWords = <String>{'1', 'true', 't', 'yes', 'y', 'on'};
const Set<String> _falseWords = <String>{'0', 'false', 'f', 'no', 'n', 'off'};
final RegExp _integer = RegExp(r'^[+-]?\d+$');

/// True when compiled for the web, by dart2js or dart2wasm. Both give ±(2^53 − 1) (5.7); dart2wasm has
/// 64-bit integers, so `identical(0, 0.0)` would miss it.
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// Renders a number the same way on the VM and the web: an integer as its digits, a double without a
/// fraction as its integer (`1.0` becomes `1`), other doubles as `double.toString`.
String renderNumber(num value) {
  if (value is int) {
    return value.toString();
  }
  final String text = value.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
