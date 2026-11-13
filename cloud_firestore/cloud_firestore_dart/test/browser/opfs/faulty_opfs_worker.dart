// The worker of example/sqlite_opfs_worker.dart with a file system that fails
// on command, for web_persistence_opfs_test.dart: the page arms a fault over
// the BroadcastChannel `opfs-faults` with a JSON message
// `{"point": "<operation>:<file>", "code": <extended result code>,
// "afterEffect": <bool>}` and waits for the reply "armed". The next matching
// operation then throws a VfsException with that code, before doing its work,
// or after it with `afterEffect` (an error after the commit point, for
// example). Operations: read, write, sync, truncate, delete; files:
// /database, /database-journal.
//
// Compiled by tool/build_web_test_assets.sh:
//
//   dart compile js -O1 -o test/browser/opfs/faulty_opfs_worker.js \
//       test/browser/opfs/faulty_opfs_worker.dart

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:web/web.dart' as web;

import '../../../example/sqlite_opfs_worker.dart' show runOpfsWorker;

/// The armed fault, if any.
String? _point;
int _code = 0;
bool _afterEffect = false;

void _check(String operation, String file, void Function() work) {
  if (_point != '$operation:$file') {
    work();
    return;
  }
  _point = null;
  if (_afterEffect) {
    work();
  }
  throw sqlite.VfsException(_code);
}

void main() {
  final web.BroadcastChannel channel = web.BroadcastChannel('opfs-faults');
  channel.onmessage = (web.MessageEvent event) {
    final Map<String, Object?> fault =
        jsonDecode((event.data! as JSString).toDart) as Map<String, Object?>;
    _point = fault['point'] as String?;
    _code = fault['code']! as int;
    _afterEffect = fault['afterEffect'] as bool? ?? false;
    channel.postMessage('armed'.toJS);
  }.toJS;
  runOpfsWorker(wrapFileSystem: _FaultyFileSystem.new);
}

final class _FaultyFileSystem extends sqlite.BaseVirtualFileSystem {
  _FaultyFileSystem(this._inner) : super(name: '${_inner.name}-faulty');

  final sqlite.VirtualFileSystem _inner;

  @override
  int xAccess(String path, int flags) => _inner.xAccess(path, flags);

  @override
  void xDelete(String path, int syncDir) =>
      _check('delete', path, () => _inner.xDelete(path, syncDir));

  @override
  String xFullPathName(String path) => _inner.xFullPathName(path);

  @override
  sqlite.XOpenResult xOpen(sqlite.Sqlite3Filename path, int flags) {
    final sqlite.XOpenResult opened = _inner.xOpen(path, flags);
    return (
      outFlags: opened.outFlags,
      file: _FaultyFile(path.path ?? '', opened.file),
    );
  }

  @override
  void xSleep(Duration duration) => _inner.xSleep(duration);
}

class _FaultyFile implements sqlite.VirtualFileSystemFile {
  _FaultyFile(this._name, this._inner);

  final String _name;
  final sqlite.VirtualFileSystemFile _inner;

  @override
  void xRead(Uint8List target, int fileOffset) =>
      _check('read', _name, () => _inner.xRead(target, fileOffset));

  @override
  void xWrite(Uint8List buffer, int fileOffset) =>
      _check('write', _name, () => _inner.xWrite(buffer, fileOffset));

  @override
  int xCheckReservedLock() => _inner.xCheckReservedLock();

  @override
  void xClose() => _inner.xClose();

  @override
  int get xDeviceCharacteristics => _inner.xDeviceCharacteristics;

  @override
  int xFileSize() => _inner.xFileSize();

  @override
  void xLock(int mode) => _inner.xLock(mode);

  @override
  void xSync(int flags) => _check('sync', _name, () => _inner.xSync(flags));

  @override
  void xTruncate(int size) =>
      _check('truncate', _name, () => _inner.xTruncate(size));

  @override
  void xUnlock(int mode) => _inner.xUnlock(mode);
}
