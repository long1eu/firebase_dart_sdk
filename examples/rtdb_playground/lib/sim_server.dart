/// A small simulated Realtime Database server for the page.
///
/// It drives a [FakeDatabaseServer] the way a server would: it watches the requests the client sends,
/// answers listens and gets from its own in-memory JSON tree, and acknowledges writes. Rules are not
/// evaluated, there is one user, and nothing is validated. This is not the real backend.
library;

import 'dart:async';

import 'package:firebase_database_dart/testing.dart';

/// One thing the simulated server did, for the page's server log.
typedef SimLog = void Function(String line);

/// The server side of the playground.
final class SimServer {
  /// Drives [fake] and writes what it does to [log].
  SimServer(this.fake, this.log);

  /// The fake the client is connected to.
  final FakeDatabaseServer fake;

  /// Receives one line per request the server handled.
  final SimLog log;

  /// What the server stores: JSON maps, strings, numbers and booleans. Never null, never an empty map.
  Map<String, Object?> data = <String, Object?>{};

  /// Called after [data] changed.
  void Function()? onChange;

  /// Whether the next write is refused with `permission_denied`.
  bool rejectNext = false;

  /// Called after a write was refused because of [rejectNext], which is false again by then.
  void Function()? onReject;

  Timer? _timer;
  int _seen = 0;
  final List<_Intent> _intents = <_Intent>[];

  /// Starts watching the requests.
  void start() => _timer ??= Timer.periodic(
    const Duration(milliseconds: 60),
    (Timer _) => _poll(),
  );

  /// Stops watching.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Whether a connection is accepted. Turning it off drops the current one, as a lost network does.
  bool get reachable => fake.acceptConnections;
  set reachable(bool value) {
    fake.acceptConnections = value;
    if (!value) {
      fake.dropConnection();
      log('connection lost');
    } else {
      log('connections accepted again');
    }
  }

  /// Tells the server what the client is about to write: a request names only the action and the path,
  /// not the data, so the page says what it sent. [transaction] replaces an earlier transaction at
  /// [path], as a retry of the handler does.
  void expectWrite(
    String action,
    String path,
    Object? value, {
    bool transaction = false,
  }) {
    final String key = _clean(path).join('/');
    if (transaction) {
      _intents.removeWhere((_Intent i) => i.transaction && i.path == key);
    }
    _intents.add(_Intent(action, key, value, transaction));
  }

  void _poll() {
    final List<String> requests = fake.requests;
    if (requests.length == _seen) {
      return;
    }
    final List<String> fresh = requests.sublist(_seen);
    _seen = requests.length;
    bool changed = false;
    // The requests are in the order they left, so answering each write as it comes answers the
    // oldest one, the order the fake requires.
    for (final String request in fresh) {
      final List<String> parts = request.split(' ');
      final String code = parts[0];
      final String path = _clean(parts[1]).join('/');
      final bool filtered = parts.length > 2;
      try {
        switch (code) {
          case 'q' when !filtered:
            fake.answerListen(path, _valueAt(path));
            log('answered listen /$path');
          case 'g' when !filtered:
            fake.answerGet(path, _valueAt(path));
            log('answered get /$path');
          case 'p' || 'm':
            changed = _answerWrite(code, path) || changed;
          case 'o' || 'om' || 'oc':
            fake.ackNextOnDisconnect();
          case 'n':
            log('unlisten /$path');
          default:
            log('ignored $request');
        }
      } on StateError {
        // The request was withdrawn before the answer, for example an unlisten.
      }
    }
    if (changed) {
      onChange?.call();
    }
  }

  /// Answers the oldest unanswered write, which is the [code] request at [path], and applies it to
  /// [data] when the page said its data. Returns whether [data] changed.
  bool _answerWrite(String code, String path) {
    final _Intent? intent = _take(code, path);
    if (rejectNext) {
      rejectNext = false;
      fake.failNextWrite('permission_denied');
      log('refused $code /$path: permission_denied');
      onReject?.call();
      return false;
    }
    fake.ackNextWrite();
    if (intent == null) {
      log('acknowledged $code /$path (the page did not say its data)');
      return false;
    }
    if (intent.action == 'set') {
      _setAt(intent.path, intent.value);
    } else {
      (intent.value! as Map<String, Object?>).forEach((String key, Object? v) {
        _setAt('${intent.path}/$key', v);
      });
    }
    log('applied ${intent.action} /${intent.path}');
    return true;
  }

  _Intent? _take(String code, String path) {
    final String action = code == 'p' ? 'set' : 'update';
    for (int i = 0; i < _intents.length; i++) {
      if (_intents[i].action == action && _intents[i].path == path) {
        return _intents.removeAt(i);
      }
    }
    return null;
  }

  Object? _valueAt(String path) {
    Object? node = data;
    for (final String key in _clean(path)) {
      if (node is Map<String, Object?> && node.containsKey(key)) {
        node = node[key];
      } else {
        return null;
      }
    }
    return node is Map<String, Object?> && node.isEmpty ? null : node;
  }

  void _setAt(String path, Object? value) {
    final List<String> keys = _clean(path);
    if (keys.isEmpty) {
      data = _prune(value) is Map<String, Object?>
          ? (_prune(value)! as Map<String, Object?>)
          : <String, Object?>{};
      return;
    }
    _put(data, keys, 0, _prune(value));
  }

  static void _put(
    Map<String, Object?> node,
    List<String> keys,
    int index,
    Object? value,
  ) {
    final String key = keys[index];
    if (index == keys.length - 1) {
      if (value == null) {
        node.remove(key);
      } else {
        node[key] = value;
      }
      return;
    }
    final Object? child = node[key];
    final Map<String, Object?> map = child is Map<String, Object?>
        ? child
        : <String, Object?>{};
    _put(map, keys, index + 1, value);
    if (map.isEmpty) {
      node.remove(key);
    } else {
      node[key] = map;
    }
  }

  /// Drops nulls and empty maps, as the server does.
  static Object? _prune(Object? value) {
    if (value is Map) {
      final Map<String, Object?> out = <String, Object?>{};
      value.forEach((Object? k, Object? v) {
        final Object? pruned = _prune(v);
        if (pruned != null) {
          out['$k'] = pruned;
        }
      });
      return out.isEmpty ? null : out;
    }
    return value;
  }

  static List<String> _clean(String path) =>
      path.split('/').where((String s) => s.isNotEmpty).toList();
}

final class _Intent {
  _Intent(this.action, this.path, this.value, this.transaction);

  /// `set` or `update`.
  final String action;
  final String path;
  final Object? value;
  final bool transaction;
}
