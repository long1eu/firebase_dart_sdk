import '../auth_storage.dart';

/// An [AuthStorage] in a file that only its owner can read. It needs `dart:io` (the Dart VM: command line tools,
/// servers, Flutter on desktop and mobile); on the web the constructor throws an [UnsupportedError]: use
/// `WebAuthStorage` there.
///
/// On the VM the file holds a JSON object of the stored values and is written atomically with mode 0600 (Linux and
/// macOS; on Windows it inherits the access control list of its directory). See the documentation of the VM
/// implementation for the details and what a stored refresh token exposes.
class FileAuthStorage implements AuthStorage {
  /// A storage in the file at [path]. Throws an [UnsupportedError] on this platform.
  FileAuthStorage(this.path) {
    throw UnsupportedError(
      'FileAuthStorage needs dart:io; use WebAuthStorage on the web.',
    );
  }

  /// The path of the file.
  final String path;

  @override
  Future<String?> read(String key) => throw UnsupportedError('No dart:io');

  @override
  Future<void> write(String key, String? value) =>
      throw UnsupportedError('No dart:io');
}
