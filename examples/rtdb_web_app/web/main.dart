// The page: a live list on the Realtime Database, a form that pushes an item,
// the connection state (`.info/connected`), a go offline / go online button
// and a panel to connect your own emulator or project.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:rtdb_web_app/app_config.dart';
import 'package:web/web.dart';

const String _storageKey = 'rtdb_web_app.settings';
const String _itemsPath = 'rtdb_web_app/items';

T _el<T extends Element>(String id) => document.getElementById(id) as T;

FirebaseDatabase? _db;
final List<StreamSubscription<Object?>> _subs = <StreamSubscription<Object?>>[];
int _generation = 0;
bool _offline = false;
// Keys of the items in the list, and the writes of this page that the server
// has not confirmed yet.
final Map<String, HTMLLIElement> _rows = <String, HTMLLIElement>{};
int _pending = 0;

void main() {
  final Map<String, String> params = Uri.base.queryParameters;
  AppConfig config = AppConfig.fromParameters(params);
  if (!config.isUsable) {
    config = _stored() ?? const AppConfig();
  }
  _fillForm(config);

  _el<HTMLFormElement>('add').onSubmit.listen((Event e) {
    e.preventDefault();
    _add();
  });
  _el<HTMLButtonElement>('toggle').onClick.listen((_) => _toggleOffline());
  _el<HTMLFormElement>('connect').onSubmit.listen((Event e) {
    e.preventDefault();
    _applyForm();
  });
  _el<HTMLButtonElement>('forget').onClick.listen((_) {
    _storage()?.removeItem(_storageKey);
    _el<HTMLInputElement>('f-remember').checked = false;
    _showError('Stored settings removed.');
  });

  _connect(config);
}

AppConfig? _stored() {
  try {
    final String? text = _storage()?.getItem(_storageKey);
    if (text == null) return null;
    final Map<String, Object?> map = jsonDecode(text) as Map<String, Object?>;
    final AppConfig config = AppConfig.fromParameters(
      map.map((String k, Object? v) => MapEntry<String, String>(k, '$v')),
    );
    return AppConfig.validate(config) == null ? config : null;
  } catch (_) {
    return null;
  }
}

Storage? _storage() {
  try {
    return window.localStorage;
  } catch (_) {
    return null;
  }
}

void _fillForm(AppConfig c) {
  _el<HTMLInputElement>('f-emulator').value = c.emulatorHost ?? '';
  _el<HTMLInputElement>('f-url').value = c.databaseUrl ?? '';
  _el<HTMLInputElement>('f-key').value = c.apiKey ?? '';
  _el<HTMLInputElement>('f-project').value = c.projectId ?? '';
  _el<HTMLInputElement>('f-remember').checked = _stored() != null;
}

void _applyForm() {
  final AppConfig config = AppConfig.fromParameters(<String, String>{
    'emulator': _el<HTMLInputElement>('f-emulator').value,
    'databaseUrl': _el<HTMLInputElement>('f-url').value,
    'apiKey': _el<HTMLInputElement>('f-key').value,
    'project': _el<HTMLInputElement>('f-project').value,
  });
  if (_el<HTMLInputElement>('f-remember').checked) {
    try {
      _storage()?.setItem(_storageKey, jsonEncode(config.toStorage()));
    } catch (_) {}
  } else {
    _storage()?.removeItem(_storageKey);
  }
  _connect(config);
}

Future<void> _disconnect() async {
  _generation++;
  for (final StreamSubscription<Object?> s in _subs) {
    unawaited(s.cancel());
  }
  _subs.clear();
  final FirebaseDatabase? old = _db;
  _db = null;
  _rows.clear();
  _el<HTMLUListElement>('items').textContent = '';
  _pending = 0;
  _offline = false;
  if (old != null) {
    final FirebaseApp app = old.app;
    try {
      await old.close();
      await app.delete();
    } catch (_) {}
  }
}

Future<void> _connect(AppConfig config) async {
  await _disconnect();
  _showError('');
  final HTMLElement notice = _el<HTMLElement>('notice');
  final HTMLButtonElement toggle = _el('toggle');
  final HTMLButtonElement submit =
      _el<HTMLFormElement>('add').querySelector('button') as HTMLButtonElement;
  final String? problem = AppConfig.validate(config);
  notice.hidden = (config.isUsable && problem == null).toJS;
  _el<HTMLElement>('backend').textContent = config.isUsable && problem == null
      ? config.label
      : 'none';
  toggle.disabled = submit.disabled = true;
  _setConnected(false);
  _setPending();
  if (problem != null) {
    _showError(problem);
    return;
  }
  if (!config.isUsable) return;

  final int generation = _generation;
  try {
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: config.apiKey ?? 'demo-key',
        appId: '1:0:web:rtdb-web-app',
        projectId: config.projectId ?? 'demo-example',
        databaseURL: config.databaseUrl,
      ),
      name: 'rtdb-web-app-$generation',
    );
    final FirebaseDatabase db = FirebaseDatabase(
      app,
      emulatorHost: config.emulatorHost,
      databaseUrl: config.databaseUrl,
    );
    _db = db;
    _listen(db, generation);
    toggle
      ..disabled = false
      ..textContent = 'Go offline';
    submit.disabled = false;
  } catch (error) {
    _showError('Could not connect: $error');
  }
}

void _listen(FirebaseDatabase db, int generation) {
  final DatabaseReference items = db.ref(_itemsPath);
  final Query ordered = items.orderByChild('at');
  void guard<T>(Stream<T> stream, void Function(T) onData) {
    _subs.add(
      stream.listen(
        (T value) {
          if (generation == _generation) onData(value);
        },
        onError: (Object error) {
          if (generation == _generation) _showError('$error');
        },
      ),
    );
  }

  guard<bool>(db.onConnected, _setConnected);
  guard<DatabaseEvent>(
    ordered.onChildAdded,
    (DatabaseEvent e) => _upsert(e.snapshot, e.previousChildKey),
  );
  // A server timestamp replaces the local estimate and can move the item.
  guard<DatabaseEvent>(
    ordered.onChildMoved,
    (DatabaseEvent e) => _place(_rows[e.snapshot.key!], e.previousChildKey),
  );
  guard<DatabaseEvent>(
    items.onChildChanged,
    (DatabaseEvent e) => _upsert(e.snapshot, null, place: false),
  );
  guard<DatabaseEvent>(items.onChildRemoved, (DatabaseEvent e) {
    _rows.remove(e.snapshot.key)?.remove();
  });
}

/// Shows [snapshot] as a row; with [place] the row goes after [previousKey] (see [_place]).
void _upsert(DataSnapshot snapshot, String? previousKey, {bool place = true}) {
  final String key = snapshot.key!;
  final Object? value = snapshot.value;
  final String text = value is Map ? '${value['text']}' : '$value';
  final HTMLLIElement row = _rows[key] ??=
      document.createElement('li') as HTMLLIElement;
  row.textContent = text;
  // A write made here and not confirmed yet is shown in italics.
  row.className = _unconfirmed.contains(key) ? 'local' : '';
  if (place) _place(row, previousKey);
}

/// Puts [row] right after the row of [previousKey], or first when there is none, unless it is there.
void _place(HTMLLIElement? row, String? previousKey) {
  if (row == null) return;
  final HTMLUListElement list = _el('items');
  final HTMLLIElement? before = previousKey == null ? null : _rows[previousKey];
  if (before == null) {
    if (row.parentNode == null || list.firstChild != row) list.prepend(row);
  } else if (row.parentNode == null || before.nextSibling != row) {
    list.insertBefore(row, before.nextSibling);
  }
}

final Set<String> _unconfirmed = <String>{};

void _add() {
  final FirebaseDatabase? db = _db;
  final HTMLInputElement input = _el('text');
  final String text = input.value.trim();
  if (db == null || text.isEmpty) return;
  input.value = '';
  final DatabaseReference ref = db.ref(_itemsPath).push();
  final String key = ref.key!;
  _unconfirmed.add(key);
  _pending++;
  _setPending();
  final int generation = _generation;
  ref
      .set(<String, Object?>{'text': text, 'at': ServerValue.timestamp})
      .then((_) {
        _unconfirmed.remove(key);
        if (generation != _generation) return;
        _pending--;
        _setPending();
        _rows[key]?.className = '';
      })
      .catchError((Object error) {
        _unconfirmed.remove(key);
        if (generation != _generation) return;
        _pending--;
        _setPending();
        _showError('The write failed: $error');
      });
}

void _toggleOffline() {
  final FirebaseDatabase? db = _db;
  if (db == null) return;
  _offline = !_offline;
  if (_offline) {
    db.goOffline();
  } else {
    db.goOnline();
  }
  _el<HTMLButtonElement>('toggle').textContent = _offline
      ? 'Go online'
      : 'Go offline';
  _setPending();
}

void _setConnected(bool connected) {
  final HTMLElement e = _el('connected');
  e.textContent = connected ? 'Connected' : 'Not connected';
  e.className = connected ? 'online' : 'offline';
}

void _setPending() {
  _el<HTMLElement>('pending').textContent = _pending == 0
      ? 'No writes waiting'
      : '$_pending write(s) waiting for the server'
            '${_offline ? ' (offline: they appear in the list at once '
                      'and are sent when you go online)' : ''}';
}

void _showError(String message) {
  _el<HTMLElement>('error').textContent = message;
}
