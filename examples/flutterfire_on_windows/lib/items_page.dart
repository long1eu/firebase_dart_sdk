import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'bootstrap.dart';

/// The collection of the app, with the official API only.
CollectionReference<Map<String, dynamic>> get items =>
    FirebaseFirestore.instance.collection(AppConfig.collection);

/// A live list of the collection: add, edit, delete, a transaction per item,
/// a batch, a query, and the snapshot metadata in a status line.
class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final TextEditingController _title = TextEditingController();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _snapshots = items
      .orderBy('createdAt')
      .snapshots(includeMetadataChanges: true);
  bool _online = !AppConfig.startOffline;
  String _queryResult = '';
  String _aggregateResult = '';
  String _error = '';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// Runs a write and shows its error, if any. The future of a write completes
  /// when the server acknowledged it, so it is not awaited by the UI: the
  /// listener shows the write at once, with hasPendingWrites.
  void _write(Future<void> Function() write) {
    write().catchError((Object e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    });
  }

  void _add() {
    final String title = _title.text.trim();
    if (title.isEmpty) {
      return;
    }
    _title.clear();
    _write(
      () => items.add(<String, dynamic>{
        'title': title,
        'priority': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  Future<void> _edit(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final String? title = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _EditDialog(initial: doc.data()?['title'] as String? ?? ''),
    );
    if (title == null || title.isEmpty) {
      return;
    }
    _write(
      () => doc.reference.update(<String, dynamic>{
        'title': title,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  /// Raises the priority by one in a transaction (read, then write).
  void _bump(DocumentReference<Map<String, dynamic>> ref) {
    _write(
      () => FirebaseFirestore.instance.runTransaction((Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> current = await tx.get(
          ref,
        );
        final int priority = current.data()?['priority'] as int? ?? 0;
        tx.update(ref, <String, dynamic>{
          'priority': priority + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }),
    );
  }

  /// Adds three items in one write batch.
  void _addBatch() {
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    for (int i = 1; i <= 3; i++) {
      batch.set(items.doc(), <String, dynamic>{
        'title': 'batch-$i',
        'priority': i,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    _write(batch.commit);
  }

  /// The items with priority 2 or more, highest first, at most three.
  Future<void> _runQuery() async {
    try {
      final QuerySnapshot<Map<String, dynamic>> result = await items
          .where('priority', isGreaterThanOrEqualTo: 2)
          .orderBy('priority', descending: true)
          .limit(3)
          .get();
      setState(() {
        _queryResult = result.docs.isEmpty
            ? '(none)'
            : result.docs
                  .map((QueryDocumentSnapshot<Map<String, dynamic>> d) {
                    return '${d['title']} (${d['priority']})';
                  })
                  .join(', ');
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  /// Count, sum and average of the priorities, computed by the server. The
  /// native Windows plugin rejects sum and average ("not supported by the
  /// Firebase C++ SDK on Windows"); cloud_firestore_dart runs them.
  Future<void> _runAggregate() async {
    try {
      final AggregateQuerySnapshot result = await items
          .aggregate(count(), sum('priority'), average('priority'))
          .get();
      setState(() {
        _aggregateResult =
            'count ${result.count}, '
            'sum ${result.getSum('priority')?.toStringAsFixed(0)}, '
            'average ${result.getAverage('priority')?.toStringAsFixed(2)}';
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _setOnline(bool online) async {
    setState(() => _online = online);
    if (online) {
      await FirebaseFirestore.instance.enableNetwork();
    } else {
      await FirebaseFirestore.instance.disableNetwork();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlutterFire on Windows'),
        actions: <Widget>[
          const Text('Network'),
          Switch(
            key: const ValueKey<String>('networkSwitch'),
            value: _online,
            onChanged: _setOnline,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _snapshots,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
            ) {
              final QuerySnapshot<Map<String, dynamic>>? data = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _StatusLine(snapshot: snapshot),
                  _buildInput(),
                  _buildActions(),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _error,
                        key: const ValueKey<String>('error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const Divider(),
                  Expanded(
                    child: data == null
                        ? const Center(
                            child: Text('Waiting for the first snapshot'),
                          )
                        : _buildList(data),
                  ),
                ],
              );
            },
      ),
    );
  }

  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              key: const ValueKey<String>('titleField'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'New item'),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const ValueKey<String>('addButton'),
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          OutlinedButton(
            key: const ValueKey<String>('batchButton'),
            onPressed: _addBatch,
            child: const Text('Add 3 in a batch'),
          ),
          OutlinedButton(
            key: const ValueKey<String>('queryButton'),
            onPressed: _runQuery,
            child: const Text('Query: priority >= 2, top 3'),
          ),
          Text(_queryResult, key: const ValueKey<String>('queryResult')),
          OutlinedButton(
            key: const ValueKey<String>('aggregateButton'),
            onPressed: _runAggregate,
            child: const Text('Count, sum, average'),
          ),
          Text(
            _aggregateResult,
            key: const ValueKey<String>('aggregateResult'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(QuerySnapshot<Map<String, dynamic>> data) {
    if (data.docs.isEmpty) {
      return const Center(child: Text('No items yet'));
    }
    return ListView(
      children: <Widget>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in data.docs)
          _buildItem(doc),
      ],
    );
  }

  Widget _buildItem(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final String title = doc.data()['title'] as String? ?? '';
    final Object? createdAt = doc.data()['createdAt'];
    final String created = createdAt is Timestamp
        ? createdAt.toDate().toUtc().toIso8601String().substring(0, 19)
        : 'server time pending';
    return ListTile(
      key: ValueKey<String>('item-$title'),
      leading: Icon(
        doc.metadata.hasPendingWrites ? Icons.cloud_upload : Icons.cloud_done,
      ),
      title: Text(title),
      subtitle: Text('priority ${doc.data()['priority']} · created $created'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            key: ValueKey<String>('bump-$title'),
            tooltip: 'Priority + 1 (transaction)',
            onPressed: () => _bump(doc.reference),
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            key: ValueKey<String>('edit-$title'),
            tooltip: 'Edit',
            onPressed: () => _edit(doc),
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            key: ValueKey<String>('delete-$title'),
            tooltip: 'Delete',
            onPressed: () => _write(doc.reference.delete),
            icon: const Icon(Icons.delete),
          ),
        ],
      ),
    );
  }
}

/// Asks for a new title. It owns its controller, which must outlive the
/// closing animation of the dialog.
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.initial});

  final String initial;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit title'),
      content: TextField(
        key: const ValueKey<String>('editField'),
        controller: _controller,
        autofocus: true,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('saveEdit'),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The metadata of the last snapshot: where it came from and whether it has
/// writes the server has not acknowledged yet.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.snapshot});

  final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot;

  @override
  Widget build(BuildContext context) {
    final QuerySnapshot<Map<String, dynamic>>? data = snapshot.data;
    final String cache = AppConfig.diskCache ? 'disk' : 'memory';
    final String text;
    if (snapshot.hasError) {
      text = 'Listener error: ${snapshot.error}';
    } else if (data == null) {
      text = 'Waiting for the first snapshot · cache: $cache';
    } else {
      text =
          '${data.docs.length} docs · isFromCache: '
          '${data.metadata.isFromCache} · hasPendingWrites: '
          '${data.metadata.hasPendingWrites} · cache: $cache';
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, key: const ValueKey<String>('status')),
    );
  }
}
