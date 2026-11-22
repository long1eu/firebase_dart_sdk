// The playground page: the real client against a small simulated server in the page.
//
// The client comes from databaseWithFakeServer; SimServer (lib/sim_server.dart) answers it. Nothing leaves
// the page: its Content-Security-Policy has connect-src 'none'. See README.md.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:rtdb_playground/sim_server.dart';
import 'package:web/web.dart' as web;

/// The most lines a log keeps.
const int _maxLines = 150;

late final FirebaseDatabase _db;
late final SimServer _sim;
final Map<int, StreamSubscription<DatabaseEvent>> _listeners =
    <int, StreamSubscription<DatabaseEvent>>{};
final Map<int, String> _listenerNames = <int, String>{};
final Map<int, String> _pending = <int, String>{};
int _nextId = 0;
int _eventCount = 0;

void main() {
  final FakeDatabaseServer fake = FakeDatabaseServer();
  _sim = SimServer(fake, (String line) => _line('server-log', line, ''))
    ..data = <String, Object?>{
      'counter': 1,
      'todos': <String, Object?>{
        'a': <String, Object?>{'title': 'Read the docs', 'done': false},
      },
    }
    ..onChange = _renderServer;
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:web:rtdbplayground',
      projectId: 'demo-rtdb-playground',
    ),
  );
  _db = databaseWithFakeServer(
    app,
    fake,
    reconnectDelay: const Duration(milliseconds: 400),
  );
  _sim.start();
  _renderServer();

  _db.onConnected.listen((bool connected) {
    final web.Element badge = _byId('conn');
    badge.textContent = connected ? 'client connected' : 'client offline';
    badge.className = connected ? 'badge on' : 'badge off';
  });
  _db.ref().onValue.listen(
    (DatabaseEvent event) => _renderTree('client-tree', event.snapshot.value),
    onError: _fail,
  );

  _byId<web.HTMLInputElement>('reachable').onChange.listen((_) {
    _sim.reachable = _byId<web.HTMLInputElement>('reachable').checked;
  });
  _byId<web.HTMLButtonElement>('reject').onClick.listen((_) {
    _sim.rejectNext = !_sim.rejectNext;
    final web.Element button = _byId('reject');
    button.setAttribute('aria-pressed', '${_sim.rejectNext}');
    button.textContent = _sim.rejectNext
        ? 'Next write will be rejected (click to cancel)'
        : 'Server rejects next write';
  });
  _form('f-set', _set);
  _form('f-update', _update);
  _form('f-push', _push);
  _form('f-remove', _remove);
  _form('f-tx', _transaction);
  _form('f-listen', _listen);
  _renderPending();
}

void _form(String id, void Function() action) {
  _byId<web.HTMLFormElement>(id).onSubmit.listen((web.Event event) {
    event.preventDefault();
    _text('error', '');
    try {
      action();
    } on Object catch (error) {
      _fail(error);
    }
  });
}

String _val(String id) => _byId<web.HTMLInputElement>(id).value.trim();
String _area(String id) => _byId<web.HTMLTextAreaElement>(id).value;

String _path(String id) =>
    _val(id).split('/').where((String s) => s.isNotEmpty).join('/');

void _fail(Object error) => _text('error', '$error');

/// Runs [write] as a pending operation: listed until its Future completes, and logged either way.
void _track(String name, Future<void> write) {
  final int id = _nextId++;
  _pending[id] = name;
  _renderPending();
  _line('events', 'local  $name', 'write');
  write
      .then<void>(
        (_) {
          _line('events', 'server confirmed  $name', 'ok');
        },
        onError: (Object error) {
          _line('events', 'rejected  $name: $error', 'error');
        },
      )
      .whenComplete(() {
        _pending.remove(id);
        _renderPending();
      });
}

void _set() {
  final String path = _path('set-path');
  final Object? value = jsonDecode(_area('set-value'));
  _sim.expectWrite('set', path, value);
  _track('set /$path ${jsonEncode(value)}', _db.ref(path).set(value));
}

void _update() {
  final String path = _path('upd-path');
  final Object? value = jsonDecode(_area('upd-value'));
  if (value is! Map<String, Object?>) {
    throw const FormatException('update needs a JSON object');
  }
  _sim.expectWrite('update', path, value);
  _track('update /$path ${jsonEncode(value)}', _db.ref(path).update(value));
}

void _push() {
  final Object? value = jsonDecode(_area('push-value'));
  final DatabaseReference ref = _db.ref(_path('push-path')).push();
  final String path = ref.path;
  _sim.expectWrite('set', path, value);
  _track('push $path ${jsonEncode(value)}', ref.set(value));
}

void _remove() {
  final String path = _path('rm-path');
  _sim.expectWrite('set', path, null);
  _track('remove /$path', _db.ref(path).remove());
}

void _transaction() {
  final String path = _path('tx-path');
  final String op = _val('tx-op');
  final int id = _nextId++;
  _pending[id] = 'transaction /$path';
  _renderPending();
  _line('events', 'local  transaction /$path ($op)', 'write');
  _db
      .ref(path)
      .runTransaction((Object? current) {
        final Object? next;
        switch (op) {
          case 'inc':
            next = current is num ? current + 1 : 1;
          case 'bang':
            next = current is String ? '$current!' : 'hello!';
          default:
            if (current != null) {
              return Transaction.abort();
            }
            next = 'first';
        }
        _sim.expectWrite('set', path, next, transaction: true);
        return Transaction.success(next);
      })
      .then<void>(
        (TransactionResult r) => _line(
          'events',
          r.committed
              ? 'transaction /$path committed ${jsonEncode(r.snapshot.value)}'
              : 'transaction /$path aborted',
          r.committed ? 'ok' : 'error',
        ),
        onError: (Object error) =>
            _line('events', 'transaction /$path failed: $error', 'error'),
      )
      .whenComplete(() {
        _pending.remove(id);
        _renderPending();
      });
}

void _listen() {
  final String path = _path('l-path');
  final String type = _val('l-type');
  final Query query = _db.ref(path);
  final Stream<DatabaseEvent> stream = switch (type) {
    'added' => query.onChildAdded,
    'changed' => query.onChildChanged,
    'removed' => query.onChildRemoved,
    _ => query.onValue,
  };
  final int id = _nextId++;
  final String name = '$type /$path';
  _listeners[id] = stream.listen(
    (DatabaseEvent e) => _line(
      'events',
      '#${++_eventCount} ${e.type.name} /$path'
          '${type == 'value' ? '' : ' key=${e.snapshot.key}'}'
          ' ${jsonEncode(e.snapshot.value)}',
      'event',
    ),
    onError: (Object error) => _line('events', '$name failed: $error', 'error'),
  );
  _listenerNames[id] = name;
  _renderListeners();
}

void _renderListeners() {
  final web.Element list = _byId('listeners');
  list.textContent = '';
  _listenerNames.forEach((int id, String name) {
    final web.Element item = web.document.createElement('li')
      ..append(web.document.createTextNode(name));
    final web.HTMLButtonElement stop =
        web.document.createElement('button') as web.HTMLButtonElement
          ..type = 'button'
          ..textContent = 'stop';
    stop.setAttribute('aria-label', 'Stop listening: $name');
    stop.onClick.listen((_) {
      unawaited(_listeners.remove(id)?.cancel());
      _listenerNames.remove(id);
      _renderListeners();
    });
    list.append(item..append(stop));
  });
}

void _renderPending() {
  final web.Element list = _byId('pending');
  list.textContent = '';
  _text('pending-count', '${_pending.length}');
  if (_pending.isEmpty) {
    list.append(
      web.document.createElement('li')
        ..className = 'empty'
        ..textContent = 'none',
    );
  }
  for (final String name in _pending.values) {
    list.append(web.document.createElement('li')..textContent = name);
  }
}

void _renderServer() => _renderTree('server-tree', _sim.data);

void _renderTree(String id, Object? value) {
  final web.Element root = _byId(id);
  root.textContent = '';
  if (value == null) {
    root.append(
      web.document.createElement('span')
        ..className = 'empty'
        ..textContent = 'null (no data)',
    );
    return;
  }
  root.append(_node(value));
}

web.Element _node(Object? value) {
  if (value is Map) {
    final web.Element ul = web.document.createElement('ul');
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final web.Element li = web.document.createElement('li')
        ..append(
          web.document.createElement('span')
            ..className = 'k'
            ..textContent = '${entry.key}: ',
        );
      final Object? child = entry.value;
      if (child is Map) {
        li.append(_node(child));
      } else {
        li.append(_leaf(child));
      }
      ul.append(li);
    }
    return ul;
  }
  return _leaf(value);
}

web.Element _leaf(Object? value) => web.document.createElement('span')
  ..className = value is String ? 's' : 'n'
  ..textContent = jsonEncode(value);

void _line(String listId, String text, String kind) {
  final web.Element list = _byId(listId);
  list.append(
    web.document.createElement('li')
      ..className = kind
      ..textContent = text,
  );
  while (list.childElementCount > _maxLines) {
    list.firstElementChild?.remove();
  }
  list.scrollTop = list.scrollHeight.toDouble();
}

T _byId<T extends web.Element>(String id) =>
    web.document.getElementById(id)! as T;

void _text(String id, String text) {
  web.document.getElementById(id)?.textContent = text;
}
