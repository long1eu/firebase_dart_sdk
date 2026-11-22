import 'dart:async';
import 'dart:io';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel;
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_open.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// A wall clock that only moves when a test moves it, and a `delay` that moves it instead of
/// waiting. [onAdvance] runs after every move (a test refreshes a live owner's lease there).
final class FakeClock {
  /// Starts at a fixed time.
  FakeClock([this.nowMs = 1767225600000]);

  /// The current time in milliseconds since the epoch. A test sets it to step the clock back.
  int nowMs;

  /// Every wait asked for through [delay].
  final List<Duration> delays = <Duration>[];

  /// Runs after each [advance].
  void Function()? onAdvance;

  /// The time, as `SqliteStoreOptions.nowMs` wants it.
  int now() => nowMs;

  /// Moves the clock by [duration].
  void advance(Duration duration) {
    nowMs += duration.inMilliseconds;
    onAdvance?.call();
  }

  /// When set, [delay] moves the clock in steps of this size, running [onAdvance] after each, so
  /// that a test can model an owner whose refresh comes late within the wait.
  Duration? delayStep;

  /// A `delay` that records [duration] and moves the clock by it.
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    final Duration? step = delayStep;
    if (step == null) {
      advance(duration);
      return;
    }
    Duration left = duration;
    while (left > Duration.zero) {
      final Duration next = left < step ? left : step;
      advance(next);
      left -= next;
    }
  }
}

/// A periodic timer that fires only when a test calls [fire]; tests also call
/// `SqliteConnection.refreshLease` themselves.
final class FakePeriodicTimer implements Timer {
  /// A timer that would fire every [period] and run the store's tick.
  FakePeriodicTimer(this.period, this._tick);

  /// The period the store asked for.
  final Duration period;

  final void Function(Timer timer) _tick;
  bool _active = true;
  int _ticks = 0;

  /// Runs the tick, as the real timer would after [period]; nothing once cancelled.
  void fire() {
    if (!_active) {
      return;
    }
    _ticks++;
    _tick(this);
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _ticks;
}

/// A temporary directory, a fake clock and the log of one test.
final class StoreFixture {
  /// A new empty directory under the system temp directory.
  StoreFixture()
    : root = Directory.systemTemp.createTempSync('rtdb_sqlite_test_');

  /// The temporary directory; the store directory is [directory] inside it.
  final Directory root;

  /// The clock of every store of this fixture.
  final FakeClock clock = FakeClock();

  /// Every message logged by the stores of this fixture.
  final List<String> log = <String>[];

  /// Every refresh timer the stores of this fixture armed, oldest first.
  final List<FakePeriodicTimer> timers = <FakePeriodicTimer>[];

  int _owners = 0;

  /// The store directory (not created: the opener creates it).
  String get directory => SqliteFiles.join(root.path, 'store');

  /// The store file name used by [open].
  static const String fileName = 'rtdb-test.sqlite';

  /// The store file path used by [open].
  String get path => SqliteFiles.join(directory, fileName);

  /// Options with this fixture's log, fake timers ([timers]) and owner ids `owner-1`, `owner-2`...
  /// [clock] replaces the fixture's [clock] (an owner whose clock differs from the observer's);
  /// [ownerId] replaces the generated owner id.
  SqliteStoreOptions options({
    int? sqliteVersionNumber,
    FakeClock? clock,
    String? ownerId,
  }) {
    final FakeClock time = clock ?? this.clock;
    return SqliteStoreOptions(
      nowMs: time.now,
      delay: time.delay,
      periodicTimer: (Duration period, void Function(Timer timer) tick) {
        final FakePeriodicTimer timer = FakePeriodicTimer(period, tick);
        timers.add(timer);
        return timer;
      },
      log: (DatabaseLogLevel level, String message) => log.add(message),
      newOwnerId: () => ownerId ?? 'owner-${++_owners}',
      sqliteVersionNumber: sqliteVersionNumber,
    );
  }

  /// Opens the store at [path] with [options].
  Future<SqliteConnection> open({
    int? sqliteVersionNumber,
    FakeClock? clock,
    String? ownerId,
  }) {
    return openSqliteStore(
      directory: directory,
      fileName: fileName,
      options: options(
        sqliteVersionNumber: sqliteVersionNumber,
        clock: clock,
        ownerId: ownerId,
      ),
    );
  }

  /// A second, raw SQLite connection to [path], as another process would have.
  sqlite.Database raw() {
    final sqlite.Database db = sqlite.sqlite3.open(path);
    db.select('PRAGMA busy_timeout = 1000');
    return db;
  }

  /// Closes a connection from [raw] (`dispose` works with sqlite3 2.x and 3.x).
  static void closeRaw(sqlite.Database db) {
    // ignore: deprecated_member_use
    db.dispose();
  }

  /// The single value of [sql] on [db].
  static Object? scalar(sqlite.Database db, String sql) =>
      db.select(sql).first.columnAt(0);

  /// Deletes the temporary directory.
  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}
