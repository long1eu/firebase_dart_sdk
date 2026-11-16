// The playground page: a live query, its documents, the snapshot events as
// they arrive, and the writes that wait for a server that is never contacted.
//
// The client runs with its network disabled, on a memory cache (see
// openOffline in lib/playground.dart): nothing leaves the page. See README.md
// for how to build and serve it.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:playground/playground.dart';
import 'package:web/web.dart' as web;

/// The most entries the event list and the timeline keep.
const int _maxEvents = 60;

late final FirebaseApp _app;
late Firestore _firestore;

/// Bumped by a reset: callbacks of the instance before it do nothing.
int _generation = 0;

StreamSubscription<QuerySnapshot<Map<String, Object?>>>? _subscription;
int _snapshotCount = 0;
int _writeCount = 0;
final List<_PendingWrite> _pending = <_PendingWrite>[];

Future<void> main() async {
  _app = FirebaseApp.withOptions(playgroundOptions);
  _setUpSelects();
  _byId<web.HTMLTextAreaElement>('w-data').value =
      '{\n  "name": "Berlin",\n  "country": "DE",\n'
      '  "population": 3755251,\n  "capital": true\n}';
  try {
    _firestore = await openOffline(_app);
  } catch (error) {
    _text('error', 'The client could not start: $error');
    return;
  }
  _byId<web.HTMLFormElement>('query').onSubmit.listen((web.Event event) {
    event.preventDefault();
    _listen();
  });
  _byId<web.HTMLFormElement>('write').onSubmit.listen((web.Event event) {
    event.preventDefault();
    _save();
  });
  _byId<web.HTMLButtonElement>('sample').onClick.listen((_) => _addSamples());
  _byId<web.HTMLButtonElement>('reset').onClick.listen((_) => _reset());
  _renderPending();
  _listen();
}

void _setUpSelects() {
  for (final String id in <String>['q-collection', 'w-collection']) {
    final web.HTMLSelectElement select = _byId(id);
    for (final String name in playgroundCollections) {
      select.append(
        web.HTMLOptionElement()
          ..value = name
          ..text = name,
      );
    }
  }
  final web.HTMLSelectElement op = _byId('q-op');
  for (final WhereOp value in WhereOp.values) {
    op.append(
      web.HTMLOptionElement()
        ..value = value.name
        ..text = value.symbol,
    );
  }
  // The first query: the most populated cities.
  _byId<web.HTMLInputElement>('q-order').value = 'population';
  _byId<web.HTMLSelectElement>('q-direction').value = 'desc';
  _byId<web.HTMLInputElement>('q-limit').value = '10';
}

QuerySpec _readQuery() {
  final String limit = _byId<web.HTMLInputElement>('q-limit').value.trim();
  return QuerySpec(
    collection: _byId<web.HTMLSelectElement>('q-collection').value,
    whereField: _byId<web.HTMLInputElement>('q-field').value.trim(),
    op: WhereOp.values.byName(_byId<web.HTMLSelectElement>('q-op').value),
    whereValue: _byId<web.HTMLInputElement>('q-value').value,
    orderField: _byId<web.HTMLInputElement>('q-order').value.trim(),
    descending: _byId<web.HTMLSelectElement>('q-direction').value == 'desc',
    limit: limit.isEmpty ? null : int.tryParse(limit),
  );
}

/// Replaces the listener with one on the query of the form.
void _listen() {
  unawaited(_subscription?.cancel());
  _subscription = null;
  _text('query-error', '');
  final QuerySpec spec = _readQuery();
  _text('query-code', spec.toDart());
  final Query<Map<String, Object?>> query;
  try {
    query = spec.build(_firestore);
  } catch (error) {
    _text('query-error', 'The client does not accept this query: $error');
    return;
  }
  _logEvent(
    kind: 'listen',
    title: 'Listening to ${spec.collection}',
    lines: <String>['Each snapshot below comes from this listener.'],
  );
  final int generation = _generation;
  _subscription = query
      .getSnapshots(MetadataChanges.include)
      .listen(
        (QuerySnapshot<Map<String, Object?>> snapshot) {
          if (generation == _generation) {
            _onSnapshot(snapshot);
          }
        },
        onError: (Object error) {
          if (generation == _generation) {
            _text('query-error', 'The listener failed: $error');
          }
        },
      );
}

void _onSnapshot(QuerySnapshot<Map<String, Object?>> snapshot) {
  _snapshotCount++;
  final SnapshotMetadata metadata = snapshot.metadata;
  _renderDocuments(snapshot);
  final List<String> changes = <String>[
    for (final DocumentChange<Map<String, Object?>> change
        in snapshot.getDocumentChanges(MetadataChanges.include))
      '${change.type.name} ${change.document.ref.path}'
          '${change.type == DocumentChangeType.removed ? '' : ' at ${change.newIndex}'}',
  ];
  _logEvent(
    kind: 'snapshot',
    title: 'Snapshot $_snapshotCount: ${snapshot.length} documents',
    flags: <String>[
      'isFromCache: ${metadata.isFromCache}',
      'hasPendingWrites: ${metadata.hasPendingWrites}',
    ],
    lines: changes.isEmpty ? <String>['no document changed'] : changes,
    marker: changes.isEmpty ? 'S' : '${changes.length}',
  );
}

void _renderDocuments(QuerySnapshot<Map<String, Object?>> snapshot) {
  final SnapshotMetadata metadata = snapshot.metadata;
  _text('docs-count', '${snapshot.length}');
  _text(
    'docs-meta',
    'Last snapshot: isFromCache ${metadata.isFromCache}, hasPendingWrites '
        '${metadata.hasPendingWrites}.',
  );
  final web.Element list = _byId('docs');
  list.textContent = '';
  if (snapshot.isEmpty) {
    list.append(
      _element(
        'li',
        className: 'empty',
        text:
            'No document matches. Press "Add sample data" or save one with '
            'the form.',
      ),
    );
    return;
  }
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in snapshot) {
    list.append(_card(doc));
  }
}

web.Element _card(QueryDocumentSnapshot<Map<String, Object?>> doc) {
  final String path = doc.ref.path;
  // A server timestamp the backend has not set yet reads as null; `estimate`
  // gives the local time instead.
  final Map<String, Object?> raw = doc.getData(ServerTimestampBehavior.none);
  final Map<String, Object?> data = doc.getData(
    ServerTimestampBehavior.estimate,
  );
  final web.Element card = _element('li', className: 'card');
  final web.Element header = _element('div', className: 'card-head')
    ..append(_element('code', text: path));
  if (doc.metadata.hasPendingWrites) {
    header.append(
      _element('span', className: 'badge pending', text: 'pending write'),
    );
  }
  card.append(header);
  final web.Element fields = _element('dl');
  for (final MapEntry<String, Object?> field in data.entries) {
    final bool estimate = raw[field.key] == null && field.value is Timestamp;
    fields
      ..append(_element('dt', text: field.key))
      ..append(
        _element('dd', text: formatValue(field.value))..append(
          _element(
            'span',
            className: 'note',
            text: estimate ? ' estimate' : '',
          ),
        ),
      );
  }
  card.append(fields);
  final web.HTMLButtonElement edit = _button('Edit', 'Edit $path')
    ..onClick.listen((_) => _edit(doc.ref, raw));
  final web.HTMLButtonElement delete = _button('Delete', 'Delete $path')
    ..className = 'danger'
    ..onClick.listen((_) => _track('delete', <String>[path], doc.ref.delete()));
  card.append(
    _element('div', className: 'actions')
      ..append(edit)
      ..append(delete),
  );
  return card;
}

void _edit(
  DocumentReference<Map<String, Object?>> reference,
  Map<String, Object?> data,
) {
  _byId<web.HTMLSelectElement>('w-collection').value = reference.parent.id;
  _byId<web.HTMLInputElement>('w-id').value = reference.id;
  final web.HTMLTextAreaElement text = _byId('w-data')
    ..value = formatDocument(data);
  text
    ..scrollIntoView()
    ..focus();
}

/// Saves the document of the write form with `set()`.
void _save() {
  _text('error', '');
  final String collection = _byId<web.HTMLSelectElement>('w-collection').value;
  final String id = _byId<web.HTMLInputElement>('w-id').value.trim();
  final Object? decoded;
  try {
    decoded = jsonDecode(_byId<web.HTMLTextAreaElement>('w-data').value);
  } on FormatException catch (error) {
    _text('error', 'The data is not valid JSON: ${error.message}');
    return;
  }
  if (decoded is! Map<String, Object?>) {
    _text('error', 'The data must be a JSON object: { "field": value }.');
    return;
  }
  try {
    final CollectionReference<Map<String, Object?>> reference = _firestore
        .collection(collection);
    final DocumentReference<Map<String, Object?>> doc = id.isEmpty
        ? reference.doc()
        : reference.doc(id);
    _track(
      'set',
      <String>[doc.path],
      doc.set(<String, Object?>{
        ...decoded,
        updatedAtField: FieldValue.serverTimestamp(),
      }),
    );
    _byId<web.HTMLInputElement>('w-id').value = '';
  } catch (error) {
    _text('error', 'The client refused the write: $error');
  }
}

/// Writes [sampleDocuments] in one batch: one entry in the queue.
void _addSamples() {
  final WriteBatch batch = _firestore.batch();
  for (final MapEntry<String, Map<String, Object?>> entry
      in sampleDocuments.entries) {
    batch.set(_firestore.doc(entry.key), <String, Object?>{
      ...entry.value,
      updatedAtField: FieldValue.serverTimestamp(),
    });
  }
  _track('batch', sampleDocuments.keys.toList(), batch.commit());
}

/// Shows a write in the queue until its future completes, which needs the
/// backend: here it never does.
void _track(String operation, List<String> paths, Future<void> done) {
  final _PendingWrite write = _PendingWrite(
    ++_writeCount,
    operation,
    paths,
    DateTime.now(),
  );
  _pending.add(write);
  _renderPending();
  _logEvent(
    kind: 'write',
    title: 'Write ${write.number}: $operation',
    lines: paths,
    marker: 'W',
  );
  final int generation = _generation;
  done.then<void>(
    (_) {
      if (generation != _generation) {
        return;
      }
      _pending.remove(write);
      _renderPending();
      _logEvent(
        kind: 'ack',
        title: 'Write ${write.number} acknowledged by the backend',
      );
    },
    onError: (Object error) {
      if (generation != _generation) {
        return;
      }
      _pending.remove(write);
      _renderPending();
      _logEvent(
        kind: 'error',
        title: 'Write ${write.number} failed',
        lines: <String>['$error'],
      );
    },
  );
}

void _renderPending() {
  final web.Element list = _byId('pending');
  list.textContent = '';
  _text('pending-count', '${_pending.length}');
  if (_pending.isEmpty) {
    list.append(
      _element('li', className: 'empty', text: 'No write is waiting.'),
    );
    return;
  }
  for (final _PendingWrite write in _pending) {
    final web.Element item = _element('li')
      ..append(
        _element(
          'span',
          className: 'op',
          text: '${write.number}. ${write.operation}',
        ),
      )
      ..append(_element('span', className: 'time', text: _time(write.at)))
      ..append(_element('span', text: write.paths.join(', ')));
    list.append(item);
  }
}

/// Clears everything: terminates the instance (its memory cache and pending
/// writes go with it) and opens a new one.
Future<void> _reset() async {
  final web.HTMLButtonElement button = _byId('reset')..disabled = true;
  try {
    _generation++;
    await _subscription?.cancel();
    _subscription = null;
    await _firestore.terminate();
    _firestore = await openOffline(_app);
    _pending.clear();
    _writeCount = 0;
    _snapshotCount = 0;
    _renderPending();
    _byId('events').textContent = '';
    _byId('timeline').textContent = '';
    _text('error', '');
    _logEvent(
      kind: 'reset',
      title: 'Reset',
      lines: <String>['A new instance with an empty memory cache.'],
    );
    _listen();
  } catch (error) {
    _text('error', 'Reset failed: $error. Reload the page.');
  } finally {
    button.disabled = false;
  }
}

/// Adds an entry to the event list (newest first) and to the timeline.
void _logEvent({
  required String kind,
  required String title,
  List<String> flags = const <String>[],
  List<String> lines = const <String>[],
  String? marker,
}) {
  final String time = _time(DateTime.now());
  final web.Element events = _byId('events');
  final web.Element entry = _element('li', className: 'event $kind')
    ..append(
      _element('div', className: 'event-head')
        ..append(_element('span', className: 'kind', text: kind))
        ..append(_element('strong', text: title))
        ..append(_element('span', className: 'time', text: time)),
    );
  if (flags.isNotEmpty) {
    final web.Element row = _element('div', className: 'flags');
    for (final String flag in flags) {
      row.append(
        _element(
          'span',
          className: flag.endsWith('true') ? 'flag on' : 'flag',
          text: flag,
        ),
      );
    }
    entry.append(row);
  }
  if (lines.isNotEmpty) {
    final web.Element list = _element('ul');
    for (final String line in lines) {
      list.append(_element('li', text: line));
    }
    entry.append(list);
  }
  events.insertBefore(entry, events.firstChild);
  while (events.childElementCount > _maxEvents) {
    events.lastElementChild!.remove();
  }

  final web.Element timeline = _byId('timeline');
  final String label = '$time $title';
  timeline.append(
    _element(
        'li',
        className: 'tick $kind',
        text: marker ?? kind[0].toUpperCase(),
      )
      ..setAttribute('title', label)
      ..setAttribute('aria-label', label),
  );
  while (timeline.childElementCount > _maxEvents) {
    timeline.firstElementChild!.remove();
  }
  timeline.scrollLeft = timeline.scrollWidth;
}

class _PendingWrite {
  _PendingWrite(this.number, this.operation, this.paths, this.at);

  final int number;
  final String operation;
  final List<String> paths;
  final DateTime at;
}

T _byId<T extends web.Element>(String id) =>
    web.document.getElementById(id)! as T;

void _text(String id, String text) {
  web.document.getElementById(id)?.textContent = text;
}

web.Element _element(String tag, {String? className, String? text}) {
  final web.Element element = web.document.createElement(tag);
  if (className != null) {
    element.className = className;
  }
  if (text != null) {
    element.textContent = text;
  }
  return element;
}

web.HTMLButtonElement _button(String text, String label) =>
    web.HTMLButtonElement()
      ..type = 'button'
      ..textContent = text
      ..setAttribute('aria-label', label);

String _time(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
      '${time.millisecond.toString().padLeft(3, '0')}';
}
