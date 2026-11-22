import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Names, removal and quarantine of the files of a store.
abstract final class SqliteFiles {
  /// The suffixes of the files SQLite keeps next to a database file: the write-ahead log, its
  /// shared-memory index and a rollback journal.
  static const List<String> sideSuffixes = <String>['-wal', '-shm', '-journal'];

  /// The infix of a file moved aside: `<file>.bad-<UTC time>`.
  static const String badInfix = '.bad-';

  /// The file name of the store of [databaseUrl] of the app named [appName]:
  /// `rtdb-<first 32 hex digits of SHA-256(appName + "\n" + databaseUrl)>.sqlite`.
  ///
  /// No app name, URL, namespace or user id appears in a path (threat model T20), and any name is
  /// safe on every file system.
  static String fileName(String appName, Uri databaseUrl) {
    final Digest digest = sha256.convert(utf8.encode('$appName\n$databaseUrl'));
    return 'rtdb-${digest.toString().substring(0, 32)}.sqlite';
  }

  /// [name] inside [directory].
  static String join(String directory, String name) {
    final String separator = Platform.pathSeparator;
    return directory.endsWith(separator) || directory.endsWith('/')
        ? '$directory$name'
        : '$directory$separator$name';
  }

  /// Moves the database file at [path] aside as `<path>.bad-<time>`, with its write-ahead log and
  /// rollback journal next to it, and deletes its shared-memory index.
  ///
  /// The log must move with its file: left behind, SQLite would replay it into the new file of the
  /// same name. Earlier `.bad-` copies of the same file are deleted first, so at most one copy is
  /// kept. Returns false when the file could not be moved (on Windows, while another handle has it
  /// open); then nothing was renamed.
  static bool moveAside(String path, DateTime now) {
    // Old copies that can not be deleted are left; the new copy is still made.
    _deleteBadCopies(path);
    final String target = '$path$badInfix${_stamp(now.toUtc())}';
    try {
      if (File(path).existsSync()) {
        File(path).renameSync(target);
      }
    } on FileSystemException {
      return false;
    }
    for (final String suffix in <String>['-wal', '-journal']) {
      final File side = File('$path$suffix');
      if (side.existsSync()) {
        try {
          side.renameSync('$target$suffix');
        } on FileSystemException {
          // A log that can not move must not stay next to the new file: delete it instead.
          _deleteQuietly(side);
        }
      }
    }
    _deleteQuietly(File('$path-shm'));
    return true;
  }

  /// Deletes the store file at [path], its side files and its `.bad-` copies; files that do not
  /// exist are skipped. The side files go first; the database file is deleted only when they are
  /// all gone (a log left next to a new file of the same name would be replayed into it). Returns
  /// the failures; empty when everything was deleted.
  static List<FileSystemException> deleteAll(String path) {
    final List<FileSystemException> failures = <FileSystemException>[];
    for (final String suffix in sideSuffixes) {
      _delete(File('$path$suffix'), failures);
    }
    if (failures.isEmpty) {
      _delete(File(path), failures);
    }
    failures.addAll(_deleteBadCopies(path));
    return failures;
  }

  /// The `.bad-` copies of the store file at [path], with their side files.
  static List<File> badCopies(String path) {
    final File file = File(path);
    final Directory directory = file.parent;
    if (!directory.existsSync()) {
      return const <File>[];
    }
    final String prefix = '${file.uri.pathSegments.last}$badInfix';
    return <File>[
      for (final FileSystemEntity entity in directory.listSync(
        followLinks: false,
      ))
        if (entity is File && entity.uri.pathSegments.last.startsWith(prefix))
          entity,
    ];
  }

  static List<FileSystemException> _deleteBadCopies(String path) {
    final List<FileSystemException> failures = <FileSystemException>[];
    for (final File copy in badCopies(path)) {
      _delete(copy, failures);
    }
    return failures;
  }

  static void _delete(File file, List<FileSystemException> failures) {
    if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    try {
      file.deleteSync();
    } on FileSystemException catch (e) {
      failures.add(e);
    }
  }

  static void _deleteQuietly(File file) {
    _delete(file, <FileSystemException>[]);
  }

  static String _stamp(DateTime utc) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}${two(utc.day)}'
        'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
  }
}
