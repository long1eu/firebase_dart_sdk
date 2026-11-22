import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'bootstrap.dart';

/// Shows the connection state, the last notes (a query ordered by a child with
/// a limit, kept in order from its child events), a field that pushes a note, a counter changed by a transaction
/// and the presence entries, one of which is this app's, with an
/// `onDisconnect` write.
class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  late final DatabaseReference _notes = _database.ref(
    '${AppConfig.root}/notes',
  );
  late final DatabaseReference _counter = _database.ref(
    '${AppConfig.root}/counter',
  );
  late final DatabaseReference _hits = _database.ref('${AppConfig.root}/hits');
  late final DatabaseReference _presence = _database.ref(
    '${AppConfig.root}/presence',
  );
  late final DatabaseReference _me = _presence.child(AppConfig.clientId);

  late final Query _notesQuery = _notes
      .orderByChild('createdAt')
      .limitToLast(10);

  final TextEditingController _text = TextEditingController();
  final List<StreamSubscription<DatabaseEvent>> _subscriptions =
      <StreamSubscription<DatabaseEvent>>[];

  bool _connected = false;
  String _status = 'Ready';

  /// The notes in the window, oldest first, as the query orders them.
  final List<DataSnapshot> _noteList = <DataSnapshot>[];
  int _count = 0;
  int _hitCount = 0;
  bool _offline = false;
  Map<String, Object?> _others = <String, Object?>{};

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll(<StreamSubscription<DatabaseEvent>>[
      _database.ref('.info/connected').onValue.listen(_onConnected),
      _notesQuery.onChildAdded.listen(_place, onError: _onError),
      _notesQuery.onChildChanged.listen(_replace, onError: _onError),
      _notesQuery.onChildMoved.listen(_place, onError: _onError),
      _notesQuery.onChildRemoved.listen(_drop, onError: _onError),
      _counter.onValue.listen((DatabaseEvent event) {
        setState(() => _count = (event.snapshot.value as int?) ?? 0);
      }, onError: _onError),
      _hits.onValue.listen((DatabaseEvent event) {
        setState(() => _hitCount = (event.snapshot.value as int?) ?? 0);
      }, onError: _onError),
      _presence.onValue.listen((DatabaseEvent event) {
        final Object? value = event.snapshot.value;
        setState(() {
          _others = value is Map
              ? value.map((Object? k, Object? v) => MapEntry('$k', v))
              : <String, Object?>{};
        });
      }, onError: _onError),
    ]);
  }

  /// Registers the `onDisconnect` write on each (re)connection: the server
  /// forgets it when the connection drops.
  Future<void> _onConnected(DatabaseEvent event) async {
    final bool connected = event.snapshot.value == true;
    setState(() => _connected = connected);
    if (!connected) {
      return;
    }
    try {
      await _me.onDisconnect().set(<String, Object?>{
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });
      await _me.set(<String, Object?>{
        'online': true,
        'lastSeen': ServerValue.timestamp,
      });
    } on FirebaseException catch (error) {
      _onError(error);
    }
  }

  /// Puts the child after the one named by `previousChildKey` (first when
  /// null), for a new child and for one that moved.
  void _place(DatabaseEvent event) {
    setState(() {
      _noteList.removeWhere((DataSnapshot n) => n.key == event.snapshot.key);
      final int previous = _noteList.indexWhere(
        (DataSnapshot n) => n.key == event.previousChildKey,
      );
      _noteList.insert(
        event.previousChildKey == null ? 0 : previous + 1,
        event.snapshot,
      );
    });
  }

  void _replace(DatabaseEvent event) {
    setState(() {
      final int index = _noteList.indexWhere(
        (DataSnapshot n) => n.key == event.snapshot.key,
      );
      if (index >= 0) {
        _noteList[index] = event.snapshot;
      }
    });
  }

  /// Also called for the oldest note when a new one pushes it out of the
  /// window of `limitToLast(10)`.
  void _drop(DatabaseEvent event) {
    setState(() {
      _noteList.removeWhere((DataSnapshot n) => n.key == event.snapshot.key);
    });
  }

  void _onError(Object error) {
    if (mounted) {
      setState(() => _status = 'Error: $error');
    }
  }

  Future<void> _push() async {
    final String text = _text.text.trim();
    if (text.isEmpty) {
      return;
    }
    _text.clear();
    try {
      final DatabaseReference ref = _notes.push();
      await ref.set(<String, Object?>{
        'text': text,
        'by': AppConfig.clientId,
        'createdAt': ServerValue.timestamp,
      });
      _setStatus('Pushed ${ref.key}');
    } on FirebaseException catch (error) {
      _setStatus('Push failed: ${error.code}');
    }
  }

  Future<void> _increment() async {
    try {
      final TransactionResult result = await _counter.runTransaction(
        (Object? value) => Transaction.success(((value as int?) ?? 0) + 1),
      );
      _setStatus(
        'Transaction ${result.committed ? 'committed' : 'aborted'}: '
        '${result.snapshot.value}',
      );
    } on FirebaseException catch (error) {
      _setStatus('Transaction failed: ${error.code}');
    }
  }

  /// Adds one on the server, without a read: the value is resolved there.
  Future<void> _hit() async {
    try {
      await _hits.set(ServerValue.increment(1));
    } on FirebaseException catch (error) {
      _setStatus('Increment failed: ${error.code}');
    }
  }

  /// Takes the client offline or online. Writes made offline show locally at
  /// once and are sent on going online.
  Future<void> _setOffline(bool offline) async {
    setState(() => _offline = offline);
    if (offline) {
      await _database.goOffline();
    } else {
      await _database.goOnline();
    }
  }

  Future<void> _remove(DataSnapshot note) async {
    try {
      await _notes.child(note.key!).remove();
    } on FirebaseException catch (error) {
      _setStatus('Remove failed: ${error.code}');
    }
  }

  Future<void> _edit(DataSnapshot note) async {
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _EditNoteDialog(initialText: '${note.child('text').value}'),
    );
    if (text == null || text.isEmpty) {
      return;
    }
    try {
      await _notes.child(note.key!).update(<String, Object?>{'text': text});
    } on FirebaseException catch (error) {
      _setStatus('Edit failed: ${error.code}');
    }
  }

  void _setStatus(String status) {
    if (mounted) {
      setState(() => _status = status);
    }
  }

  @override
  void dispose() {
    for (final StreamSubscription<DatabaseEvent> subscription
        in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int online = _others.values
        .where((Object? v) => v is Map && v['online'] == true)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database on Linux'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              key: const ValueKey<String>('connection'),
              avatar: Icon(
                Icons.circle,
                size: 12,
                color: _connected ? Colors.green : Colors.red,
              ),
              label: Text(_connected ? 'Connected' : 'Offline'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('noteField'),
                    controller: _text,
                    decoration: const InputDecoration(labelText: 'New note'),
                    onSubmitted: (_) => _push(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey<String>('pushButton'),
                  onPressed: _push,
                  child: const Text('Push'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                OutlinedButton(
                  key: const ValueKey<String>('counterButton'),
                  onPressed: _increment,
                  child: const Text('Count with a transaction'),
                ),
                Text(
                  'Counter: $_count',
                  key: const ValueKey<String>('counter'),
                ),
                OutlinedButton(
                  key: const ValueKey<String>('hitButton'),
                  onPressed: _hit,
                  child: const Text('Count with increment(1)'),
                ),
                Text('Hits: $_hitCount', key: const ValueKey<String>('hits')),
                Switch(
                  key: const ValueKey<String>('offlineSwitch'),
                  value: _offline,
                  onChanged: _setOffline,
                ),
                const Text('Offline'),
                Text(
                  'Online: $online of ${_others.length}',
                  key: const ValueKey<String>('presence'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Last ${_noteList.length} notes (newest first)'),
            const Divider(),
            Expanded(
              child: _noteList.isEmpty
                  ? const Center(child: Text('No notes yet'))
                  : ListView(
                      children: <Widget>[
                        for (final DataSnapshot note in _noteList.reversed)
                          ListTile(
                            key: ValueKey<String>('note-${note.key}'),
                            title: Text('${note.child('text').value}'),
                            subtitle: Text('${note.child('by').value}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  key: ValueKey<String>('edit-${note.key}'),
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(note),
                                ),
                                IconButton(
                                  key: ValueKey<String>('delete-${note.key}'),
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _remove(note),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            Text(_status, key: const ValueKey<String>('status')),
          ],
        ),
      ),
    );
  }
}

/// The edit dialog. It owns its text controller, so the controller lives until the dialog's
/// closing animation has ended; disposing it when `showDialog` returns is too early.
class _EditNoteDialog extends StatefulWidget {
  const _EditNoteDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditNoteDialog> createState() => _EditNoteDialogState();
}

class _EditNoteDialogState extends State<_EditNoteDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit note'),
      content: TextField(
        key: const ValueKey<String>('editField'),
        controller: _field,
        autofocus: true,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('editSave'),
          onPressed: () => Navigator.pop(context, _field.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
