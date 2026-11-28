import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../model.dart';
import '../store.dart';

/// A store in a JSON file in [directory], `firebase_error_reporting.json` by default.
///
/// Each save writes a temporary file of its own next to it and renames it over the old one, so a crash during a
/// write leaves the previous state. A state larger than [maxFileBytes] is saved without its oldest events, so
/// the store never writes a file it would refuse to read; a file larger than that is not read (the reporter
/// then starts empty).
///
/// One reporter per file: two processes on one file overwrite each other's queue.
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

  /// The largest file written or read: 8 MiB.
  static const int maxFileBytes = 8 * 1024 * 1024;

  static final Random _random = Random();
  static int _counter = 0;

  File get _file => File('${directory.path}${Platform.pathSeparator}$fileName');

  @override
  Future<ErrorReportingState> load() async {
    final File file = _file;
    if (!file.existsSync()) {
      return ErrorReportingState.empty;
    }
    final RandomAccessFile handle = await file.open();
    try {
      final int length = await handle.length();
      if (length > maxFileBytes) {
        throw FileSystemException('The state file is too large.', file.path);
      }
      return decodeState(utf8.decode(await handle.read(length)));
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> save(ErrorReportingState state) async {
    List<int> bytes = utf8.encode(encodeState(state));
    if (bytes.length > maxFileBytes) {
      final List<ErrorEvent> queue = <ErrorEvent>[...state.queue];
      while (bytes.length > maxFileBytes && queue.isNotEmpty) {
        queue.removeAt(0);
        bytes = utf8.encode(
          encodeState(
            ErrorReportingState(
              user: state.user,
              collectionEnabled: state.collectionEnabled,
              queue: queue,
            ),
          ),
        );
      }
    }
    final File file = _file;
    final File temporary = File(
      '${file.path}.$pid.${_counter++}.${_random.nextInt(1 << 32)}.tmp',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } on Object {
      try {
        if (temporary.existsSync()) {
          await temporary.delete();
        }
      } on Object {
        // Leave it; the next save uses another name.
      }
      rethrow;
    }
  }
}
