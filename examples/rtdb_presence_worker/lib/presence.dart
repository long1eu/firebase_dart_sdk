// The presence record of one worker, and the list of who is online.

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';

/// Where the records live: `status/<id>` holds `{state, lastChanged, heartbeat}`.
const String statusPath = 'status';

/// Keeps `status/<id>` true to the connection of this process.
///
/// Why the order matters. The server knows only what it was told before the
/// link broke. If the worker wrote `online` first and registered the
/// onDisconnect after, a drop between the two calls would leave `online` in
/// the database for good: nobody would ever write `offline`. So on every
/// connect the worker first asks the server to write `offline` when the link
/// ends, waits until the server has acknowledged that, and only then writes
/// `online`. Whatever happens next, the server holds the write that undoes it.
///
/// Why it is repeated on every connect. A registration lives in the server's
/// session, not in the database: a new connection starts without one, and the
/// client never persists them. So `.info/connected` turning true means "register
/// again", whether this is the first connect or the tenth.
class PresenceWorker {
  PresenceWorker(
    this.database, {
    required this.workerId,
    this.heartbeat = const Duration(seconds: 10),
    this.log = print,
  }) : _status = database.ref('$statusPath/$workerId');

  final FirebaseDatabase database;
  final String workerId;
  final Duration heartbeat;
  final void Function(String line) log;

  final DatabaseReference _status;
  StreamSubscription<bool>? _connection;
  Timer? _timer;
  bool _stopping = false;
  // Counts the connects; an attempt that finds a newer number is stale.
  int _generation = 0;
  // True from the acknowledged `online` write to the next drop.
  bool _online = false;
  final Completer<void> _failed = Completer<void>();

  /// Starts listening to `.info/connected` and returns at once. Completes the
  /// future of [done] with an error if the rules refuse the registration.
  void start() {
    _connection = database.onConnected.listen(
      _onConnected,
      onError: (Object error) => _fail('.info/connected failed: $error'),
    );
    _timer = Timer.periodic(heartbeat, (_) => _beat());
  }

  /// Completes with an error when the worker cannot keep its record.
  Future<void> get failed => _failed.future;

  void _fail(String message) {
    if (!_failed.isCompleted) _failed.completeError(StateError(message));
  }

  void _onConnected(bool connected) {
    final int generation = ++_generation;
    if (!connected) {
      // The server applied the onDisconnect write; the client applies it
      // locally too and forgets it. Nothing to do until the next connect.
      _online = false;
      log('$workerId: disconnected');
      return;
    }
    unawaited(_goOnline(generation));
  }

  Future<void> _goOnline(int generation) async {
    try {
      // 1. Tell the server what to write when the link ends...
      await _status.onDisconnect.update(_offline());
      // ...2. and only after it answered, say that we are here. A new connect
      // or a drop during the wait makes this attempt stale.
      if (generation != _generation || _stopping) return;
      await _status.update(<String, Object?>{
        'state': 'online',
        'lastChanged': ServerValue.timestamp,
        'heartbeat': ServerValue.timestamp,
      });
      if (generation != _generation || _stopping) return;
      _online = true;
      log('$workerId: online');
    } on FirebaseDatabaseException catch (error) {
      if (error.code == 'disconnected' || error.code == 'database-closed') {
        // The link dropped before the server answered, so the registration
        // may not exist. `online` was not written; the next connect event
        // registers again and goes on from there.
        log('$workerId: link dropped while registering, will retry');
        return;
      }
      _fail('${error.code}: ${error.message}');
    }
  }

  Map<String, Object?> _offline() => <String, Object?>{
    'state': 'offline',
    'lastChanged': ServerValue.timestamp,
  };

  Future<void> _beat() async {
    // Offline writes would pile up in the queue; the beat has no meaning
    // before `online` was written or after the link dropped.
    if (!_online || _stopping || !database.isConnected) return;
    try {
      await _status.child('heartbeat').set(ServerValue.timestamp);
    } on FirebaseDatabaseException catch (error) {
      log('$workerId: heartbeat failed: ${error.code}');
    }
  }

  /// Writes `offline`, cancels the onDisconnect and closes the database.
  ///
  /// The explicit write comes first because a clean stop does not break the
  /// link by itself in a way the server can tell from a pause; the cancel
  /// comes second so that the registered write cannot fire later and
  /// overwrite a newer record of a restarted worker with the same id. Each
  /// step has a timeout: while the backend is unreachable the writes do not
  /// complete, and the process must still exit. Returns whether both steps
  /// were acknowledged.
  Future<bool> stop({Duration timeout = const Duration(seconds: 5)}) async {
    if (_stopping) return true;
    _stopping = true;
    _timer?.cancel();
    await _connection?.cancel();
    bool clean = true;
    try {
      await _status.update(_offline()).timeout(timeout);
    } catch (error) {
      clean = false;
      log('$workerId: offline write not acknowledged: $error');
    }
    try {
      await _status.onDisconnect.cancel().timeout(timeout);
    } catch (error) {
      clean = false;
      log('$workerId: onDisconnect.cancel not acknowledged: $error');
    }
    // Fails what is still pending with `database-closed`; nothing waits on it.
    await database.close();
    return clean;
  }
}

/// Prints who is online, from one query, until [stop] completes.
///
/// The query keeps the children whose `state` is `online`. With a rule
/// `".indexOn": "state"` at `status` the server filters; without it the
/// client downloads the whole list and filters here (fine for a demo).
Future<void> watchOnline(
  FirebaseDatabase database, {
  required Future<void> stop,
  void Function(String line) log = print,
}) async {
  final Query online = database
      .ref(statusPath)
      .orderByChild('state')
      .equalTo('online');
  final StreamSubscription<DatabaseEvent> subscription = online.onValue.listen((
    DatabaseEvent event,
  ) {
    final List<String> ids = <String>[
      for (final DataSnapshot child in event.snapshot.children)
        _describe(child, database.estimatedServerTime),
    ];
    log(
      ids.isEmpty
          ? 'online: nobody'
          : 'online (${ids.length}): ${ids.join(', ')}',
    );
  }, onError: (Object error) => log('watch failed: $error'));
  await stop;
  await subscription.cancel();
}

String _describe(DataSnapshot child, DateTime now) {
  final Object? beat = child.child('heartbeat').value;
  if (beat is! num) return child.key ?? '?';
  final int age = now
      .difference(DateTime.fromMillisecondsSinceEpoch(beat.toInt()))
      .inSeconds;
  return '${child.key} (beat ${age < 0 ? 0 : age}s ago)';
}
