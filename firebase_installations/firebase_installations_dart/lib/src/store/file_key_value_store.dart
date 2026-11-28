import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:firebase_installations_dart/src/exception.dart';
import 'package:firebase_installations_dart/src/logger.dart';
import 'package:firebase_installations_dart/src/store/key_value_store.dart';
import 'package:meta/meta.dart';

/// The largest file read: 16 MiB. A larger one counts as absent.
const int _fileCap = 16 * 1024 * 1024;

/// How old a leftover temporary file must be before the start of a store deletes it.
const Duration _staleTemporary = Duration(hours: 1);

/// The names of the temporary files the store creates: `.<64 hex>.json.<32 hex>.tmp`.
final RegExp _temporaryName = RegExp(
  r'^\.[0-9a-f]{64}\.json\.[0-9a-f]{32}\.tmp$',
);

/// A [KeyValueStore] in a directory of the file system (Dart VM: command-line tools, servers, Flutter
/// desktop).
///
/// One file per key, named by the SHA-256 of the key, written atomically (a temporary file renamed over
/// the old one). Calls run one at a time, in order. An [update] whose transform returns the value it was
/// given writes nothing. A value over 16 MiB is refused with `storage-error`; an entry at a key's path
/// that is not a regular file (a directory, a pipe) counts as absent.
///
/// **One process owns the directory.** The first call takes an exclusive OS lock on
/// `<directory>/.owner.lock` and keeps it until [close]; while another process holds it every call
/// throws `FirebaseInstallationsException('storage-error')`. Two stores of one isolate on the same
/// directory are refused with a [StateError], also when their first calls overlap; the directory is
/// free again when the [close] of its store completes. On Linux and macOS the OS lock does not separate isolates
/// of one process: do not give the same directory to stores in two isolates.
///
/// **Permissions.** The directory is created when missing. On Linux and macOS the first call runs
/// `chmod 700` on it and checks that no other user can access it, else it throws `storage-error`. On
/// Windows use a directory in the user's profile (`%APPDATA%\<app>` or `%LOCALAPPDATA%\<app>`). The
/// files hold the installation's refresh token unencrypted: other programs of the same user can read it.
///
/// ```dart
/// final FileKeyValueStore store = FileKeyValueStore(
///   '${Platform.environment['HOME']}/.config/my_tool/firebase',
/// );
/// ```
final class FileKeyValueStore implements KeyValueStore {
  /// A store in [directory]. Nothing is read or created until the first call.
  ///
  /// [logger] receives warnings (never values).
  FileKeyValueStore(
    this.directory, {
    InstallationsLogger? logger,
    @visibleForTesting
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runCommand,
    @visibleForTesting DateTime Function()? clock,
  }) : _logger = logger,
       _runCommand = runCommand ?? Process.run,
       _clock = clock ?? DateTime.now;

  /// The directory of the store, as given to the constructor.
  final String directory;

  final InstallationsLogger? _logger;
  final Future<ProcessResult> Function(String, List<String>) _runCommand;
  final DateTime Function() _clock;

  /// The canonical paths of the open stores of this isolate.
  static final Set<String> _openPaths = <String>{};
  static final Random _random = Random.secure();

  Future<void> _last = Future<void>.value();
  Future<void>? _closing;
  String? _canonical;
  RandomAccessFile? _lock;

  @override
  Future<String?> read(String key) => _run(() => _read(key));

  @override
  Future<void> write(String key, String? value) =>
      _run(() => _write(key, value));

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) => _run(() async {
    final String? current = await _read(key);
    final String? next = transform(current);
    if (next == null || next != current) {
      await _write(key, next);
    }
    return next;
  });

  @override
  Stream<String> get changes => const Stream<String>.empty();

  /// Releases the store: calls made before it still run, then the OS lock is released and the directory
  /// is free for another store. Every call of `close` completes when that is done.
  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await _last;
    final String? canonical = _canonical;
    final RandomAccessFile? lock = _lock;
    _canonical = null;
    _lock = null;
    try {
      await lock?.close();
    } finally {
      if (canonical != null) {
        _openPaths.remove(canonical);
      }
    }
  }

  /// Runs [action] after every earlier call, in order, once the store has started.
  Future<T> _run<T>(Future<T> Function() action) {
    if (_closing != null) {
      return Future<T>.error(StateError('The FileKeyValueStore was closed.'));
    }
    final Future<T> next = _last.then((_) async {
      await _start();
      return action();
    });
    _last = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  // Start (first use).

  Future<void> _start() async {
    if (_canonical != null) {
      return;
    }
    final Directory dir = Directory(directory);
    final String canonical;
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      canonical = dir.resolveSymbolicLinksSync();
    } on FileSystemException catch (error, stackTrace) {
      throw _storageError(
        'the store directory could not be created',
        error,
        stackTrace,
      );
    }
    // Registered before the first await, so a second store whose first call overlaps this one is refused.
    if (!_openPaths.add(canonical)) {
      throw StateError(
        'Another FileKeyValueStore of this isolate uses this directory.',
      );
    }
    RandomAccessFile? lock;
    try {
      lock = _takeLock(canonical);
      await _restrict(canonical);
    } on Object {
      lock?.closeSync();
      _openPaths.remove(canonical);
      rethrow;
    }
    _lock = lock;
    _canonical = canonical;
    _deleteStaleTemporaries(canonical);
  }

  RandomAccessFile _takeLock(String canonical) {
    final RandomAccessFile file;
    try {
      file = File(
        _join(canonical, '.owner.lock'),
      ).openSync(mode: FileMode.append);
    } on FileSystemException catch (error, stackTrace) {
      throw _storageError(
        'the lock file of the store directory could not be opened',
        error,
        stackTrace,
      );
    }
    try {
      file.lockSync();
    } on FileSystemException catch (error, stackTrace) {
      file.closeSync();
      throw _storageError(
        'the store directory is in use by another process',
        error,
        stackTrace,
      );
    }
    return file;
  }

  /// `chmod 700` on [path] and a check of its mode (Linux and macOS).
  Future<void> _restrict(String path) async {
    if (!Platform.isLinux && !Platform.isMacOS) {
      return;
    }
    const String problem = 'the store directory must be private to the user';
    final ProcessResult result;
    try {
      result = await _runCommand('chmod', <String>['700', path]);
    } on Exception catch (error, stackTrace) {
      throw _storageError(problem, error, stackTrace);
    }
    final FileStat stat = FileStat.statSync(path);
    if (result.exitCode != 0 ||
        stat.type != FileSystemEntityType.directory ||
        stat.mode & 0x3f != 0) {
      throw _storageError(problem);
    }
  }

  void _deleteStaleTemporaries(String canonical) {
    final DateTime limit = _clock().subtract(_staleTemporary);
    final List<FileSystemEntity> entities;
    try {
      entities = Directory(canonical).listSync();
    } on FileSystemException {
      _log('Could not list the store directory to delete old temporary files.');
      return;
    }
    bool failed = false;
    for (final FileSystemEntity entity in entities) {
      final String name = entity.uri.pathSegments.last;
      if (entity is! File || !_temporaryName.hasMatch(name)) {
        continue;
      }
      try {
        if (entity.statSync().modified.isBefore(limit)) {
          entity.deleteSync();
        }
      } on FileSystemException {
        failed = true;
      }
    }
    if (failed) {
      _log('Could not delete old temporary files of the store.');
    }
  }

  // Files.

  File _fileOf(String key) {
    final String name = sha256.convert(utf8.encode(key)).toString();
    return File(_join(_canonical!, '$name.json'));
  }

  Future<String?> _read(String key) async {
    final File file = _fileOf(key);
    final FileStat stat = file.statSync();
    if (stat.type == FileSystemEntityType.notFound) {
      return null;
    }
    if (stat.type != FileSystemEntityType.file) {
      _log('A stored value is not a regular file; it is treated as absent.');
      return null;
    }
    if (stat.size > _fileCap) {
      _log('A stored value is larger than 16 MiB; it is treated as absent.');
      return null;
    }
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (error, stackTrace) {
      throw _storageError(
        'a stored value could not be read',
        error,
        stackTrace,
      );
    }
    if (bytes.length > _fileCap) {
      return null;
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      _log('A stored value is not UTF-8; it is treated as absent.');
      return null;
    }
  }

  Future<void> _write(String key, String? value) async {
    final File target = _fileOf(key);
    if (value == null) {
      try {
        if (target.existsSync()) {
          await target.delete();
        }
      } on FileSystemException catch (error, stackTrace) {
        throw _storageError(
          'a stored value could not be removed',
          error,
          stackTrace,
        );
      }
      return;
    }
    final List<int> bytes = utf8.encode(value);
    if (bytes.length > _fileCap) {
      throw _storageError('a value larger than 16 MiB cannot be stored');
    }
    final String name = target.uri.pathSegments.last;
    final File temporary = File(
      _join(_canonical!, '.$name.${_randomHex()}.tmp'),
    );
    try {
      await temporary.create(exclusive: true);
      final RandomAccessFile file = await temporary.open(mode: FileMode.write);
      try {
        await file.writeFrom(bytes);
        await file.flush();
      } finally {
        await file.close();
      }
      _removeEmptyDirectoryAt(target.path);
      await temporary.rename(target.path);
    } on FileSystemException catch (error, stackTrace) {
      try {
        if (temporary.existsSync()) {
          temporary.deleteSync();
        }
      } on FileSystemException {
        _log('Could not delete a temporary file of the store.');
      }
      throw _storageError(
        'a value could not be written to the store directory',
        error,
        stackTrace,
      );
    }
  }

  /// A rename cannot replace a directory: an empty one at [path] (a damaged store) is removed first. One
  /// with content is left, and the rename fails with `storage-error`.
  static void _removeEmptyDirectoryAt(String path) {
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.directory) {
      Directory(path).deleteSync();
    }
  }

  static String _randomHex() {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String _join(String directory, String name) =>
      '$directory${Platform.pathSeparator}$name';

  void _log(String message) {
    _logger?.call(InstallationsLogLevel.warning, message);
  }

  FirebaseInstallationsException _storageError(
    String problem, [
    Object? cause,
    StackTrace? stackTrace,
  ]) => FirebaseInstallationsException(
    code: 'storage-error',
    message: 'FileKeyValueStore: $problem.',
    cause: cause,
    stackTrace: stackTrace,
  );
}
