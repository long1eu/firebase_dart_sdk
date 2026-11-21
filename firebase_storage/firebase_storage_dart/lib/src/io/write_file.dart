/// Writing a download to a file without leaving a partial file behind.
@internal
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:meta/meta.dart';

final math.Random _random = math.Random.secure();

/// Writes [data] to a new sibling of [file], then renames it to [file], replacing a file already there.
/// Returns the number of bytes written.
///
/// When [data] fails, or writing does, the sibling is deleted, [file] is left as it was and the error is
/// rethrown.
@internal
Future<int> writeStreamToFile(Stream<List<int>> data, File file) async {
  // An unpredictable name, created exclusively: a file or link planted at that path fails the download
  // instead of receiving its bytes.
  final File temp = await File(
    '${file.path}.${_hex(4)}${_hex(4)}.part',
  ).create(exclusive: true);
  final RandomAccessFile output;
  try {
    output = await temp.open(mode: FileMode.writeOnly);
  } on Object {
    await _deleteQuietly(temp);
    rethrow;
  }
  int written = 0;
  try {
    try {
      await for (final List<int> chunk in data) {
        await output.writeFrom(chunk);
        written += chunk.length;
      }
    } finally {
      await output.close();
    }
    await temp.rename(file.path);
    return written;
  } on Object {
    await _deleteQuietly(temp);
    rethrow;
  }
}

String _hex(int bytes) => <String>[
  for (int i = 0; i < bytes; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

Future<void> _deleteQuietly(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // Already gone; the error that matters is the one being rethrown.
  }
}
