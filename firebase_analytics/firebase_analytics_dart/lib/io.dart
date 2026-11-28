/// File storage for `firebase_analytics_dart`, for programs that run on dart:io.
///
/// Not available on the web; the main library does not import it.
library;

import 'dart:convert';
import 'dart:io';

import 'firebase_analytics_dart.dart';

/// An [AnalyticsStore] that keeps one file per key in [directory].
///
/// Each write goes to a temporary file that then replaces the old one, so a crash leaves either the old or
/// the new value, never half of one. The directory is created on the first write. File names are the
/// base64url form of the key, so any key maps to one file.
///
/// The files hold the client id, the user id, user properties and unsent events. Put them where the user's
/// other application data lives (for example the application support directory) and not in a shared
/// location.
final class FileAnalyticsStore implements AnalyticsStore {
  /// A store in [directory].
  FileAnalyticsStore(this.directory);

  /// Where the files are kept.
  final Directory directory;

  File _file(String key) => File(
    '${directory.path}${Platform.pathSeparator}'
    '${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}.json',
  );

  @override
  Future<String?> read(String key) async {
    final File file = _file(key);
    try {
      return await file.readAsString();
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    final File file = _file(key);
    if (value == null) {
      try {
        await file.delete();
      } on PathNotFoundException {
        // Already gone.
      }
      return;
    }
    await directory.create(recursive: true);
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  }
}
