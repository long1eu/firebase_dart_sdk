// The sequence of examples/flutterfire_database_on_linux run through the fake server: push, edit, then
// ten pushes, each with ServerValue.timestamp, under orderByChild('createdAt').limitToLast(10), with the
// server's clock ahead of or behind the client's estimate. The child events are replayed through the
// page's list logic (_place, _replace, _drop), which must end with the server's window, newest last.

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

void main() {
  for (final Duration skew in <Duration>[
    const Duration(seconds: 5),
    const Duration(seconds: -5),
    Duration.zero,
  ]) {
    test('push, edit, ten pushes; server clock ${skew.inSeconds}s off', () {
      fakeTime((FakeTime time) => _run(Harness(time), skew));
    });
  }
}

void _run(Harness h, Duration skew) {
  final DatabaseReference notes = h.ref('notes');
  final Query query = notes.orderByChild('createdAt').limitToLast(10);
  final Map<String, String> names = <String, String>{};
  final List<String> page = <String>[];
  String name(String? key) => key == null ? '-' : names[key] ?? key;

  void place(DatabaseEvent e) {
    page.remove(e.snapshot.key);
    final int previous = page.indexOf(e.previousChildKey ?? '');
    page.insert(e.previousChildKey == null ? 0 : previous + 1, e.snapshot.key!);
  }

  void record(String tag, DatabaseEvent e) =>
      h.log.add('$tag(${name(e.snapshot.key)},${name(e.previousChildKey)})');

  query.onChildAdded.listen((DatabaseEvent e) {
    record('A', e);
    place(e);
  });
  query.onChildChanged.listen((DatabaseEvent e) => record('C', e));
  query.onChildMoved.listen((DatabaseEvent e) {
    record('M', e);
    place(e);
  });
  query.onChildRemoved.listen((DatabaseEvent e) {
    record('R', e);
    page.remove(e.snapshot.key);
  });
  h.settle();
  h.server.answerListen(
    'notes',
    null,
    query: <String, Object?>{'i': 'createdAt', 'l': 10, 'vf': 'r'},
  );
  h.settle();

  void ack() {
    h.server.serverTime = DateTime.now().add(skew);
    h.server.ackLastWrite();
    h.settle();
  }

  void pushNote(String label) {
    final DatabaseReference ref = notes.push();
    names[ref.key!] = label;
    h.log.add('push $label');
    ref.set(<String, Object?>{
      'text': label,
      'createdAt': ServerValue.timestamp,
    });
    // Before the ack the note may sort out of a full window: with the server ahead, the local estimate
    // is older than the notes already acknowledged.
    h.settle();
    h.elapse(const Duration(milliseconds: 20));
    ack();
    expect(page.map(name), contains(label), reason: '${h.log}');
    h.elapse(const Duration(milliseconds: 20));
  }

  pushNote('hello');
  final String hello = names.keys.single;
  h.log.add('edit hello');
  notes.child(hello).update(<String, Object?>{'text': 'edited'});
  h.settle();
  ack();
  for (int i = 0; i < 10; i++) {
    pushNote('note $i');
  }
  expect(page.map(name), <String>[for (int i = 0; i < 10; i++) 'note $i']);
}
