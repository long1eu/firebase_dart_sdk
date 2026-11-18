import 'dart:io';

/// The value of the environment variable [name], or null when it is not set or empty.
String? environmentVariable(String name) {
  final String? value = Platform.environment[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

/// The language of the process as a BCP 47 tag (`en-US`), from [Platform.localeName] (`en_US.UTF-8` on Linux and
/// macOS, `en-US` on Windows), or null for the POSIX locale (`C`, `POSIX`) and when it is unknown.
String? deviceLanguage() => languageTagOf(Platform.localeName);

/// [localeName] as a BCP 47 tag: the encoding (`.UTF-8`) and modifier (`@euro`) are dropped and `_` becomes `-`.
String? languageTagOf(String localeName) {
  String tag = localeName.trim();
  final int cut = tag.indexOf(RegExp('[.@]'));
  if (cut >= 0) {
    tag = tag.substring(0, cut);
  }
  tag = tag.replaceAll('_', '-');
  if (tag.isEmpty || tag == 'C' || tag == 'POSIX') {
    return null;
  }
  return tag;
}
