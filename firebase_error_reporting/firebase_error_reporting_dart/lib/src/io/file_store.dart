import 'dart:io';

import '../store.dart';

/// A store in a JSON file in [directory], `firebase_error_reporting.json` by default.
///
/// It writes a temporary file next to it and renames it over the old one, so a crash during a write leaves
/// the previous state. A file larger than 4 MiB is not read: the reporter starts empty.
final class FileErrorReportingStore implements ErrorReportingStore {
  /// A store in [directory], which must exist. [fileName] names the file.
  FileErrorReportingStore(
    this.directory, {
    this.fileName = 'firebase_error_reporting.json',
  });

  /// The directory of the file.
  final Directory directory;

  /// The name of the file.
  final String fileName;

  static const int _maxFileBytes = 4 * 1024 * 1024;

  File get _file => File('${directory.path}${Platform.pathSeparator}$fileName');

  @override
  Future<ErrorReportingState> load() async {
    final File file = _file;
    if (!file.existsSync()) {
      return ErrorReportingState.empty;
    }
    if (file.lengthSync() > _maxFileBytes) {
      throw FileSystemException('The state file is too large.', file.path);
    }
    return decodeState(await file.readAsString());
  }

  @override
  Future<void> save(ErrorReportingState state) async {
    final File file = _file;
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(encodeState(state), flush: true);
    await temporary.rename(file.path);
  }
}
