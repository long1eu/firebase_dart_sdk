/// The platform pieces of the client: the default language (5.6) and page visibility (5.9).
///
/// One conditional import picks `platform_io.dart` on the VM and `platform_web.dart` in browsers.
library;

export 'package:firebase_remote_config_dart/src/platform_web.dart'
    if (dart.library.io) 'package:firebase_remote_config_dart/src/platform_io.dart';

/// Whether the page is hidden, for the realtime open rule of 5.9.
abstract interface class Visibility {
  /// True while the page is hidden (web); always false on the VM.
  bool get isHidden;

  /// Emits the new [isHidden] when it changes; never emits on the VM.
  Stream<bool> get changes;
}

/// Reduces a locale name to a BCP 47 tag (5.6): the part before `.` or `@`, `_` replaced by `-`
/// (`en_US.UTF-8` becomes `en-US`); an empty result becomes `en`.
String normalizeLanguageTag(String locale) {
  int end = locale.length;
  for (final String separator in const <String>['.', '@']) {
    final int index = locale.indexOf(separator);
    if (index >= 0 && index < end) {
      end = index;
    }
  }
  final String tag = locale.substring(0, end).replaceAll('_', '-').trim();
  return tag.isEmpty ? 'en' : tag;
}
