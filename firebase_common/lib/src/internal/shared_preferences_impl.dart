// File created by
// Lung Razvan <long1eu>
// on 18/10/2018

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_common/src/internal/shared_preferences.dart';
import 'package:firebase_common/src/util/log.dart';
import 'package:isolate/isolate_runner.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';

class SharedPreferencesImpl implements SharedPreferences {
  static const String _tag = 'SharedPreferencesImpl';
  static const bool _debug = true;

  /// If a fsync takes more than _maxFsyncDurationMilliseconds ms, warn
  static const int _maxFsyncDurationMilliseconds = 256;

  /// Current memory state (always increasing)
  static int _currentMemoryStateGeneration = 0;

  /// Latest memory state that was committed to disk
  static int _diskStateGeneration = 0;

  /// Time (and number of instances) of file-system sync requests
  static int _numSync = 0;

  final IsolateRunner isolateRunner;
  final File _file;
  final String fileName;
  final File _backupFile;
  final StreamController<String> _onChangeSink;

  Map<String, dynamic> _map;
  int _diskWritesInFlight = 0;

  SharedPreferencesImpl._(
    this.isolateRunner,
    this._file,
    this._backupFile,
    this._map,
  )   : fileName = basenameWithoutExtension(_file.path),
        _onChangeSink = StreamController<String>.broadcast();

  static Future<SharedPreferences> init(File file,
      {bool forceRefresh = false}) async {
    if (!file.existsSync()) {
      file.createSync(recursive: true);
      await file.writeAsString('{}');
    }
    final File backupFile = _makeBackupFile(file);

    const bool loaded = false;
    if (!loaded || forceRefresh) {
      _currentMemoryStateGeneration = 0;
      _diskStateGeneration = 0;
      _numSync = 0;

      final IsolateRunner isolate =
          instance?.isolateRunner ?? await IsolateRunner.spawn();
      final Map<String, dynamic> results = await isolate
          .run(_loadFromDisk, <String>[file.path, backupFile.path]);

      if (forceRefresh) {
        instance = null;
      }

      return instance ??=
          SharedPreferencesImpl._(isolate, file, backupFile, results);
    } else {
      return instance;
    }
  }

  static SharedPreferencesImpl instance;

  static File _makeBackupFile(File prefsFile) {
    return File('${prefsFile.path}.bak');
  }

  @override
  Map<String, dynamic> get all => Map<String, Object>.from(_map);

  @override
  dynamic operator [](String key) => _map[key];

  @override
  String getString(String key, {String defValue}) {
    final String v = _map[key];
    return v ?? defValue;
  }

  @override
  List<String> getStringList(String key, {List<String> defValues}) {
    final List<String> v = _map[key]?.cast<String>();
    return v ?? defValues;
  }

  @override
  int getInt(String key, {int defValue}) {
    final int v = _map[key];
    return v ?? defValue;
  }

  @override
  double getDouble(String key, {double defValue}) {
    final double v = _map[key];
    return v ?? defValue;
  }

  @override
  bool getBool(String key, {bool defValue}) {
    final bool v = _map[key];
    return v ?? defValue;
  }

  @override
  bool contains(String key) {
    return _map.containsKey(key);
  }

  @override
  Editor edit() => EditorImpl(this);

  @override
  Stream<String> get onChange => _onChangeSink.stream;

  @visibleForTesting
  Future<SharedPreferences> reset() => init(_file, forceRefresh: true);

  /// Enqueue an already-committed-to-memory result to be written to disk.
  ///
  /// They will be written to disk one-at-a-time in the order that they're
  /// enqueued.
  Future<void> _enqueueDiskWrite(
      _MemoryCommitResult mcr, bool isFromSyncCommit) async {
    final bool wasEmpty = _diskWritesInFlight == 1;
    if (wasEmpty) {
      final List<bool> result = await WorkerQueue().enqueue(() {
        return isolateRunner.run(_writeToFile, <dynamic>[
          mcr.toJson(),
          _file.path,
          _backupFile.path,
          isFromSyncCommit
        ]);
      });

      mcr.setDiskWriteResult(wasWritten: result[0], result: result[1]);
      _diskWritesInFlight--;
      return;
    }
  }
}

class EditorImpl implements Editor {
  final Map<String, Object> _modified = <String, Object>{};
  final SharedPreferencesImpl preferencesImpl;

  EditorImpl(this.preferencesImpl);

  bool _clear = false;

  @override
  void operator []=(String key, dynamic value) => _modified[key] = value;

  @override
  void putString(String key, String value) => _modified[key] = value;

  @override
  void putStringList(String key, List<String> values) =>
      _modified[key] = values;

  @override
  void putInt(String key, int value) => _modified[key] = value;

  @override
  void putDouble(String key, double value) => _modified[key] = value;

  @override
  void putBool(String key, bool value) => _modified[key] = value;

  @override
  void remove(String key) => _modified[key] = this;

  @override
  void clear() => _clear = true;

  @override
  void apply() {
    final DateTime startTime = DateTime.now();
    final _MemoryCommitResult mcr = _commitToMemory();
    preferencesImpl._enqueueDiskWrite(mcr, false).then((_) {
      if (SharedPreferencesImpl._debug && mcr.wasWritten) {
        Log.d(
            SharedPreferencesImpl._tag,
            '${preferencesImpl.fileName}:${mcr.memoryStateGeneration} applied '
            'after ${DateTime.now().difference(startTime).inMilliseconds} ms');
      }
    });

    // Okay to notify the listeners before it's hit disk because the listeners
    // should always get the same SharedPreferences instance back, which has the
    // changes reflected in memory.
    _notifyListeners(mcr);
  }

  @override
  Future<bool> commit() async {
    final DateTime startTime = DateTime.now();
    final _MemoryCommitResult mcr = _commitToMemory();

    try {
      await preferencesImpl._enqueueDiskWrite(mcr, true);
    } catch (e) {
      return false;
    }

    if (SharedPreferencesImpl._debug) {
      final int duration = DateTime.now().difference(startTime).inMilliseconds;

      Log.d(
          SharedPreferencesImpl._tag,
          '${preferencesImpl.fileName}:${mcr.memoryStateGeneration}  '
          'committed after $duration ms');
    }

    _notifyListeners(mcr);
    return mcr.writeToDiskResult;
  }

  // Returns true if any changes were made
  _MemoryCommitResult _commitToMemory() {
    int memoryStateGeneration;
    List<String> keysModified;
    Map<String, Object> mapToWriteToDisk;

    // We optimistically don't make a deep copy until a memory commit comes in
    // when we're already writing to disk.
    if (preferencesImpl._diskWritesInFlight > 0) {
      // We can't modify our _map as a currently in-flight write owns it. Clone
      // it before modifying it.
      preferencesImpl._map = Map<String, dynamic>.from(preferencesImpl._map);
    }
    mapToWriteToDisk = preferencesImpl._map;
    preferencesImpl._diskWritesInFlight++;

    if (preferencesImpl._onChangeSink.hasListener) {
      keysModified = <String>[];
    }

    bool changesMade = false;

    if (_clear) {
      if (preferencesImpl._map.isNotEmpty) {
        changesMade = true;
        preferencesImpl._map.clear();
      }
      _clear = false;
    }

    for (MapEntry<String, Object> e in _modified.entries) {
      final String k = e.key;
      final Object v = e.value;
      // "this" is the magic value for a removal mutation. In addition, setting
      // a value to "null" for a given key is specified to be equivalent to
      // calling remove on that key.
      if (v == this || v == null) {
        if (!preferencesImpl._map.containsKey(k)) {
          continue;
        }
        preferencesImpl._map.remove(k);
      } else {
        if (preferencesImpl._map.containsKey(k)) {
          final Object existingValue = preferencesImpl._map[k];
          if (existingValue != null && existingValue == v) {
            continue;
          }
        }
        preferencesImpl._map[k] = v;
      }

      changesMade = true;
      if (preferencesImpl._onChangeSink.hasListener) {
        keysModified.add(k);
      }
    }

    _modified.clear();

    if (changesMade) {
      SharedPreferencesImpl._currentMemoryStateGeneration++;
    }

    memoryStateGeneration = SharedPreferencesImpl._currentMemoryStateGeneration;

    return _MemoryCommitResult(
      memoryStateGeneration,
      keysModified,
      mapToWriteToDisk,
    );
  }

  void _notifyListeners(final _MemoryCommitResult mcr) {
    if (mcr.keysModified == null || mcr.keysModified.isEmpty) {
      return;
    }

    for (int i = mcr.keysModified.length - 1; i >= 0; i--) {
      final String key = mcr.keysModified[i];
      preferencesImpl._onChangeSink.add(key);
    }
  }
}

// Return value from EditorImpl#commitToMemory()
class _MemoryCommitResult {
  final int memoryStateGeneration;
  final List<String> keysModified;
  final Map<String, Object> mapToWriteToDisk;

  bool writeToDiskResult = false;
  bool wasWritten = false;

  _MemoryCommitResult(
      this.memoryStateGeneration, this.keysModified, this.mapToWriteToDisk);

  factory _MemoryCommitResult.fromJson(Map<String, dynamic> json) {
    final int memoryStateGeneration = json['memoryStateGeneration'];
    final List<String> keysModified = json['keysModified'];
    final Map<String, dynamic> mapToWriteToDisk = json['mapToWriteToDisk'];

    return _MemoryCommitResult(
        memoryStateGeneration, keysModified, mapToWriteToDisk);
  }

  void setDiskWriteResult({bool wasWritten, bool result}) {
    this.wasWritten = wasWritten;
    writeToDiskResult = result;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'memoryStateGeneration': memoryStateGeneration,
      'keysModified': keysModified,
      'mapToWriteToDisk': mapToWriteToDisk,
    };
  }
}

Future<Map<String, dynamic>> _loadFromDisk(List<String> paths) async {
  final File _file = File(paths[0]);
  final File _backupFile = File(paths[1]);

  if (_backupFile.existsSync()) {
    await _file.delete();
    await _backupFile.rename(_file.path);
  }

  Map<String, Object> map;

  try {
    try {
      final String data = await _file.readAsString();
      final Map<dynamic, dynamic> json = jsonDecode(data);
      map = json.cast<String, dynamic>();
    } catch (e) {
      Log.w(SharedPreferencesImpl._tag, 'Cannot read ${_file.path} $e');
    }
  } catch (_) {}

  return map ?? <String, dynamic>{};
}

Future<List<bool>> _writeToFile(List<dynamic> args) async {
  final Map<String, dynamic> commitResult = args[0];
  final String filePath = args[1];
  final String backupPath = args[2];
  final bool isFromSyncCommit = args[3];

  final _MemoryCommitResult mcr = _MemoryCommitResult.fromJson(commitResult);
  final File file = File(filePath);
  final File backupFile = File(backupPath);

  DateTime startTime;
  DateTime existsTime;
  DateTime backupExistsTime;
  DateTime writeTime;
  DateTime fsyncTime;
  DateTime deleteTime;

  if (SharedPreferencesImpl._debug) {
    startTime = DateTime.now();
  }

  final bool fileExists = file.existsSync();

  if (SharedPreferencesImpl._debug) {
    existsTime = DateTime.now();

    // Might not be set, hence init them to a default value
    backupExistsTime = existsTime;
  }

  // Rename the current file so it may be used as a backup during the next
  // read
  if (fileExists) {
    bool needsWrite = false;

    // Only need to write if the disk state is older than this commit
    if (SharedPreferencesImpl._diskStateGeneration <
        mcr.memoryStateGeneration) {
      if (isFromSyncCommit) {
        needsWrite = true;
      } else {
        // No need to persist intermediate states. Just wait for the latest
        // state to be persisted.
        if (SharedPreferencesImpl._currentMemoryStateGeneration ==
            mcr.memoryStateGeneration) {
          needsWrite = true;
        }
      }
    }

    if (!needsWrite) {
      return <bool>[false, true];
    }

    final bool backupFileExists = backupFile.existsSync();

    if (SharedPreferencesImpl._debug) {
      backupExistsTime = DateTime.now();
    }

    if (!backupFileExists) {
      await file.rename(backupFile.path);
    } else {
      await file.delete();
    }
  }

  // Attempt to write the file, delete the backup and return true as
  // atomically as possible. If any exception occurs, delete the new file;
  // next time we will restore from the backup.
  try {
    writeTime = DateTime.now();
    await file.writeAsString(jsonEncode(mcr.mapToWriteToDisk));
    fsyncTime = DateTime.now();

    // Writing was successful, delete the backup file if there is one.
    await backupFile.delete();

    if (SharedPreferencesImpl._debug) {
      deleteTime = DateTime.now();
    }

    SharedPreferencesImpl._diskStateGeneration = mcr.memoryStateGeneration;

    if (SharedPreferencesImpl._debug) {
      Log.d(
          SharedPreferencesImpl._tag,
          'write: ${existsTime.difference(startTime)}/'
          'backup: ${backupExistsTime.difference(startTime)}/'
          'write: ${writeTime.difference(startTime)}/'
          'fsync: ${fsyncTime.difference(startTime)}/'
          'delete: ${deleteTime.difference(startTime)}');
    }

    final int fsyncDuration = fsyncTime.difference(writeTime).inMicroseconds;
    SharedPreferencesImpl._numSync++;

    if (SharedPreferencesImpl._debug ||
        SharedPreferencesImpl._numSync.remainder(1024) == 0 ||
        fsyncDuration > SharedPreferencesImpl._maxFsyncDurationMilliseconds) {
      Log.d(
          SharedPreferencesImpl._tag,
          'Time required to fsync ${basename(file.path)}: '
          '$fsyncDuration microseconds.\n');
    }

    return <bool>[true, true];
  } catch (e) {
    Log.w(SharedPreferencesImpl._tag, 'writeToFile: Got exception: $e');
  }

  // Clean up an unsuccessfully written file
  if (file.existsSync()) {
    try {
      await file.delete();
    } catch (e) {
      Log.e(SharedPreferencesImpl._tag,
          "Couldn't clean up partially-written file $file");
    }
  }

  print('\n');
  return <bool>[false, false];
}

typedef Task<TResult> = Future<TResult> Function();

class _TaskQueueEntry<T> {
  Task<T> function;
  Completer<T> completer;

  _TaskQueueEntry(this.function) : completer = Completer<T>();
}

/// A helper class that allows to schedule/queue [Function]s on a single queue.
class WorkerQueue {
  static final WorkerQueue _instance = WorkerQueue._();

  factory WorkerQueue() => _instance;

  WorkerQueue._();

  final Queue<_TaskQueueEntry<void>> _tasks = Queue<_TaskQueueEntry<void>>();

  Completer<void> _recentActiveCompleter;

  /// Schedules a task and returns a [Future] which will complete when the task
  /// has been finished.
  ///
  /// The task will be append to the queue and run after every task added before
  /// has been executed.
  Future<T> enqueue<T>(Task<T> function) async {
    final _TaskQueueEntry<T> taskEntry = _TaskQueueEntry<T>(function);

    final bool listWasEmpty = _tasks.isEmpty;
    _tasks.add(taskEntry);

    // Only run the just added task in case the queue hasn't been used yet or
    // the last task has been executed
    if (_recentActiveCompleter == null ||
        _recentActiveCompleter.isCompleted && listWasEmpty) {
      _runNext();
    }

    return await taskEntry.completer.future;
  }

  /// Queue and run this task immediately after every other already queued task.
  /// Unlike [enqueue], returns void instead of a Future for use when we have no
  /// need to 'wait' on the task completing.
  void enqueueAndForget<T>(Task<T> task) => enqueue<T>(task);

  /// Runs the next available [Task] in the queue.
  void _runNext() {
    if (_tasks.isNotEmpty) {
      final _TaskQueueEntry<dynamic> taskEntry = _tasks.first;
      _recentActiveCompleter = taskEntry.completer;

      taskEntry.function().then((dynamic value) {
        Future<void>(() {
          _tasks.removeFirst();
          _runNext();
        });
        taskEntry.completer.complete(value);
      }).catchError((dynamic error) {
        Future<void>(() {
          _tasks.removeFirst();
          _runNext();
        });
        taskEntry.completer.completeError(error);
        //panic(error);
      });
    }
  }
}
