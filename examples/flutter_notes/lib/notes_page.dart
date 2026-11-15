import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:flutter/material.dart';

import 'note.dart';

/// The list of notes, with add, edit and delete.
class NotesPage extends StatefulWidget {
  const NotesPage({super.key, required this.firestore});

  final Firestore firestore;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  late final CollectionReference<Note> _notes = widget.firestore
      .collection('notes')
      .withConverter<Note>(const NoteConverter());

  // Created once, not in build(): each call to getSnapshots starts a new
  // listener. MetadataChanges.include also delivers the snapshots in which
  // only isFromCache or hasPendingWrites changed, so the status line and the
  // pending marks follow the connection and the acknowledgements.
  late final Stream<QuerySnapshot<Note>> _snapshots = _notes
      .orderBy('updatedAt', Direction.descending)
      .getSnapshots(MetadataChanges.include);

  /// Starts a write without waiting for it. The listener shows the change at
  /// once; the future completes only when the server acknowledged it, which
  /// offline can take until the next start of the app.
  void _write(Future<void> write) {
    unawaited(
      write.catchError((Object error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Not saved: $error')));
        }
      }),
    );
  }

  Future<void> _edit([DocumentSnapshot<Note>? existing]) async {
    final Note? note = await showDialog<Note>(
      context: context,
      builder: (BuildContext context) => _NoteDialog(note: existing?.data),
    );
    if (note == null) {
      return;
    }
    // doc() makes the id on the device, so this works offline too.
    final DocumentReference<Note> ref = existing?.ref ?? _notes.doc();
    _write(ref.set(note));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      floatingActionButton: FloatingActionButton(
        onPressed: _edit,
        tooltip: 'Add a note',
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot<Note>>(
        stream: _snapshots,
        builder:
            (BuildContext context, AsyncSnapshot<QuerySnapshot<Note>> state) {
              if (state.hasError) {
                return Center(child: Text('Error: ${state.error}'));
              }
              final QuerySnapshot<Note>? snapshot = state.data;
              if (snapshot == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(
                children: <Widget>[
                  _StatusLine(metadata: snapshot.metadata),
                  Expanded(child: _buildList(snapshot)),
                ],
              );
            },
      ),
    );
  }

  Widget _buildList(QuerySnapshot<Note> snapshot) {
    if (snapshot.isEmpty) {
      return const Center(child: Text('No notes yet.'));
    }
    final List<DocumentSnapshot<Note>> docs = snapshot.docs;
    return ListView.builder(
      itemCount: docs.length,
      itemBuilder: (BuildContext context, int index) {
        final DocumentSnapshot<Note> doc = docs[index];
        final Note note = doc.data!;
        return ListTile(
          title: Text(note.title),
          subtitle: note.body.isEmpty
              ? null
              : Text(note.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => _edit(doc),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (doc.metadata.hasPendingWrites)
                const Tooltip(
                  message: 'Not yet on the server',
                  child: Icon(Icons.cloud_upload_outlined),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () => _write(doc.ref.delete()),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Says where the list comes from, from the metadata of the snapshot.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.metadata});

  final SnapshotMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text) = switch ((
      metadata.isFromCache,
      metadata.hasPendingWrites,
    )) {
      (true, true) => (
        Icons.cloud_off,
        'Offline: changes are saved on this device and sent later',
      ),
      (true, false) => (Icons.cloud_off, 'Offline: showing the saved notes'),
      (false, true) => (Icons.cloud_upload_outlined, 'Sending changes'),
      (false, false) => (Icons.cloud_done_outlined, 'Up to date'),
    };
    return Material(
      color: metadata.isFromCache
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(dense: true, leading: Icon(icon), title: Text(text)),
    );
  }
}

/// Asks for the title and the text of a note.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({this.note});

  final Note? note;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.note?.title,
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.note?.body,
  );

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    if (_title.text.trim().isEmpty) {
      return;
    }
    Navigator.of(
      context,
    ).pop(Note(title: _title.text.trim(), body: _body.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.note == null ? 'New note' : 'Edit note'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
            onSubmitted: (_) => _submit(),
          ),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Text'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
