import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ChmodNative32 = Int32 Function(Pointer<Utf8> path, Uint32 mode);
typedef _ChmodNative16 = Int32 Function(Pointer<Utf8> path, Uint16 mode);
typedef _ChmodDart = int Function(Pointer<Utf8> path, int mode);

/// File modes on macOS and Linux, where `dart:io` can read a mode ([FileStat.mode]) but not set
/// one: `chmod(2)` of the C library through `dart:ffi`.
///
/// SQLite gives its `-wal` and `-shm` files the mode of the database file, so a database file
/// created with [privateFile] keeps the whole store private to the user. Windows has no POSIX
/// modes; there [forCurrentPlatform] returns null and the per-user access list of `%LOCALAPPDATA%`
/// applies.
final class PosixFileMode {
  PosixFileMode._(this._chmod);

  /// Owner read, write and search: the mode of a store directory this package creates.
  static const int privateDirectory = 0x1C0; // 0700

  /// Owner read and write: the mode of a store file.
  static const int privateFile = 0x180; // 0600

  /// The permission bits of group and others.
  static const int groupAndOtherBits = 0x3F; // 0077

  final _ChmodDart _chmod;

  /// `chmod` of the C library of this process, or null on Windows or where it can not be found.
  static PosixFileMode? forCurrentPlatform() {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return null;
    }
    try {
      final DynamicLibrary libc = DynamicLibrary.process();
      // mode_t is 16 bits on macOS and 32 bits on Linux.
      final _ChmodDart chmod = Platform.isMacOS
          ? libc.lookupFunction<_ChmodNative16, _ChmodDart>('chmod')
          : libc.lookupFunction<_ChmodNative32, _ChmodDart>('chmod');
      return PosixFileMode._(chmod);
    } on ArgumentError {
      return null;
    }
  }

  /// The permission bits (the low nine bits) of the file or directory at [path].
  static int permissionBits(String path) =>
      FileStat.statSync(path).mode & 0x1FF;

  /// Sets the permission bits of [path] to [mode]. Returns false when `chmod` failed.
  bool setMode(String path, int mode) {
    final Pointer<Utf8> nativePath = path.toNativeUtf8();
    try {
      return _chmod(nativePath, mode) == 0;
    } finally {
      malloc.free(nativePath);
    }
  }

  /// Clears the group and other bits of [path] when any is set. Returns false when `chmod` failed.
  bool makePrivate(String path, {required int mode}) {
    if (permissionBits(path) & groupAndOtherBits == 0) {
      return true;
    }
    return setMode(path, mode);
  }
}
