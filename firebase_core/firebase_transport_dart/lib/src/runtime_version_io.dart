import 'dart:io';

/// The version of the Dart runtime: the first word of `Platform.version` (for example `3.8.0`),
/// without the channel, date and platform that follow it, so that it is one token of the
/// `X-Goog-Api-Client` header.
String get dartRuntimeVersion => Platform.version.split(' ').first;
