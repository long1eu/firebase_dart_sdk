import 'dart:io';

/// The version of the Dart runtime: the first word of `Platform.version`
/// (for example `3.12.2`), without the channel, date and platform that follow
/// it, so that it is a single token of the `x-goog-api-client` header.
String get dartRuntimeVersion => Platform.version.split(' ').first;
