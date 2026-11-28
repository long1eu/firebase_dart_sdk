import 'dart:async';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_app_check_dart/src/app_check_token.dart';
import 'package:firebase_app_check_dart/src/clocks.dart';
import 'package:firebase_app_check_dart/src/logger.dart';
import 'package:firebase_app_check_dart/src/token_record.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:meta/meta.dart';

/// How long the read before an adoption may take. A slower read counts as "no record".
const Duration _adoptReadLimit = Duration(milliseconds: 500);

/// The stored session token of one app: the record under one key of a [KeyValueStore].
///
/// No method throws and none fails a token request: every failure of the store is logged once per
/// operation and the instance continues in memory. The store is never closed here, and only the
/// session token is ever written: no limited-use token, no debug token.
@internal
final class TokenStore {
  /// The record under [key] of [store]. [appName] is used in log lines only.
  TokenStore({
    required KeyValueStore store,
    required String key,
    required Clocks clocks,
    required AppCheckLogger? logger,
    required String appName,
  }) : _store = store,
       _key = key,
       _clocks = clocks,
       _appName = appName,
       _failed = logOnceAt(logger, AppCheckLogLevel.warning),
       _ignored = logOnceAt(logger, AppCheckLogLevel.info);

  final KeyValueStore _store;
  final String _key;
  final Clocks _clocks;
  final String _appName;
  final LogOnce _failed;
  final LogOnce _ignored;
  bool _closed = false;

  /// The first read: the stored token, or null when there is none, when it was rejected or when
  /// the store failed.
  ///
  /// A rejected value is logged once per reason (not when it merely expired) and removed, unless
  /// another writer replaced it in the meantime; nobody waits for the removal. This method has no
  /// time limit of its own: the caller decides how long it waits.
  Future<SessionToken?> load() async {
    final String? value = await _read();
    if (value == null || _closed) {
      return null;
    }
    final RecordParse parsed = parseRecord(value, _clocks);
    final String? reason = parsed.reason;
    if (reason == null) {
      return parsed.token;
    }
    if (reason != recordExpired) {
      _ignored(reason, storedTokenIgnoredText(_appName, reason));
    }
    unawaited(_removeIfUnchanged(value));
    return null;
  }

  /// Writes [token] over whatever the store holds. Not awaited by anyone: a failure is logged and
  /// the token stays in memory.
  void save(SessionToken token) {
    if (_closed) {
      return;
    }
    unawaited(_write(encodeRecord(token)));
  }

  /// The read before an adoption: the stored token when it is valid and was issued later than
  /// [current] on the wall clock, or when there is no [current]; null otherwise.
  ///
  /// Tokens are ordered by issue time, never by expiry. A read slower than 500 ms, a failing store
  /// and a rejected value all count as "no record".
  Future<SessionToken?> readIfIssuedAfter(SessionToken? current) async {
    final String? value = await _readWithin(_adoptReadLimit);
    if (value == null || _closed) {
      return null;
    }
    final SessionToken? stored = parseRecord(value, _clocks).token;
    if (stored == null) {
      return null;
    }
    if (current != null && !stored.issuedWall.isAfter(current.issuedWall)) {
      return null;
    }
    return stored;
  }

  /// One event each time another writer changed the record, where the storage can tell (IndexedDB
  /// only). It carries no value: a hint to read again.
  Stream<void> get changed {
    try {
      return _store.changes
          .where((String key) => key == _key)
          .map<void>((String _) {})
          .handleError((Object _) => _logFailure(StoreOperation.read));
    } on Object {
      _logFailure(StoreOperation.read);
      return const Stream<void>.empty();
    }
  }

  /// Stops writing and logging. The store stays open and the record stays: it expires by itself.
  void close() {
    _closed = true;
  }

  Future<String?> _read() async {
    try {
      return await _store.read(_key);
    } on Object {
      _logFailure(StoreOperation.read);
      return null;
    }
  }

  /// [_read], or null when it takes longer than [limit]. The late answer is dropped.
  Future<String?> _readWithin(Duration limit) {
    final Completer<String?> done = Completer<String?>();
    final Timer timer = Timer(limit, () {
      if (!done.isCompleted) {
        done.complete(null);
      }
    });
    unawaited(
      _read().then<void>((String? value) {
        timer.cancel();
        if (!done.isCompleted) {
          done.complete(value);
        }
      }),
    );
    return done.future;
  }

  Future<void> _write(String record) async {
    try {
      await _store.write(_key, record);
    } on Object {
      _logFailure(StoreOperation.write);
    }
  }

  /// Removes the record when it still is [value]: a record that another writer stored since the
  /// read is left alone.
  Future<void> _removeIfUnchanged(String value) async {
    try {
      await _store.update(
        _key,
        (String? current) => current == value ? null : current,
      );
    } on Object {
      _logFailure(StoreOperation.remove);
    }
  }

  void _logFailure(StoreOperation operation) {
    if (_closed) {
      return;
    }
    _failed(operation.name, storeFailedText(_appName, operation));
  }
}
