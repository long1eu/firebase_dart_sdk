import 'dart:convert';

import 'package:firebase_remote_config_platform_interface/firebase_remote_config_platform_interface.dart';

/// A FlutterFire [RemoteConfigValue] holding a text as UTF-8 bytes.
///
/// Its conversions are FlutterFire's: `asBool` is true only for `true` (any
/// case) and `1`, `asInt` and `asDouble` fall back to 0 for text that does
/// not parse.
final class DartRemoteConfigValue extends RemoteConfigValue {
  /// A value holding [text], from [source].
  DartRemoteConfigValue(String text, ValueSource source)
    : super(utf8.encode(text), source);
}
