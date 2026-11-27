// The sequence of examples/flutterfire_database_on_linux run through the fake server: push, edit, then
// ten pushes, each with ServerValue.timestamp, under orderByChild('createdAt').limitToLast(10), with the
// server's clock ahead of or behind the client's estimate. The child events are replayed through the
// page's list logic (_place, _replace, _drop), which must end with the server's window, newest last.
// The offline step follows: goOffline, a push into the full window, then goOnline with the server
// confirming the write with a time other than the local estimate.

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

const Map<String, Object?> _wireQuery = <String, Object?>{
  'i': 'createdAt',
  'l': 10,
  'vf': 'r',
};

void main() {
  for (final Duration skew in <Duration>[
    const Duration(seconds: 5),
    const Duration(seconds: -5),
    Duration.zero,
  ]) {
    test('push, edit, ten pushes; server clock ${skew.inSeconds}s off', () {
      fakeTime((FakeTime time) => _NotesPage(Harness(time), skew).tenPushes());
    });
  }

  for (final Duration skew in <Duration>[
    Duration.zero,
    const Duration(seconds: -5),
  ]) {
    test(
      'offline push into a full window shows at once; server clock ${skew.inSeconds}s off',
      () {
        fakeTime((FakeTime time) {
          final _NotesPage p = _NotesPage(Harness(time), skew)..tenPushes();
          p.h.log.clear();
          final int before = DateTime.now().millisecondsSinceEpoch;
          final String offline = p.pushOffline();
          final int after = DateTime.now().millisecondsSinceEpoch;

          // Removed before added, as the JS event generator orders them.
          expect(p.h.log, <String>[
            'push written offline',
            'R(note 0,-)',
            'A(written offline,note 9)',
          ]);
          final int estimate = p.added[offline]!['createdAt']! as int;
          expect(estimate, inInclusiveRange(before, after));
          expect(p.page.map(p.name), <String>[
            for (int i = 1; i < 10; i++) 'note $i',
            'written offline',
          ]);

          p.h.log.clear();
          final int confirmed = p.goOnlineAndConfirm(skew);
          expect(confirmed, isNot(estimate));
          // The sort value changed, so child_moved comes too (JS eventGenerator, indexedValueChanged),
          // with the note still last.
          expect(p.h.log, <String>[
            'M(written offline,note 9)',
            'C(written offline,note 9)',
          ]);
          expect(p.changed[offline]!['createdAt'], confirmed);
          expect(p.page.map(p.name), <String>[
            for (int i = 1; i < 10; i++) 'note $i',
            'written offline',
          ]);
        });
      },
    );
  }

  test(
    'offline push with the server clock 5s ahead sorts out of the window until confirmed',
    () {
      const Duration skew = Duration(seconds: 5);
      fakeTime((FakeTime time) {
        final _NotesPage p = _NotesPage(Harness(time), skew)..tenPushes();
        p.h.log.clear();
        p.pushOffline();
        // The estimate (local clock, no offset from the fake handshake) is older than the ten notes.
        expect(p.h.log, <String>['push written offline']);

        p.h.log.clear();
        p.goOnlineAndConfirm(skew);
        expect(p.h.log, <String>['R(note 0,-)', 'A(written offline,note 9)']);
        expect(p.page.map(p.name), <String>[
          for (int i = 1; i < 10; i++) 'note $i',
          'written offline',
        ]);
      });
    },
  );
}

/// The page's list logic over the fake server, with the server's copy of the notes.
final class _NotesPage {
  _NotesPage(this.h, this.skew) {
    query.onChildAdded.listen((DatabaseEvent e) {
      record('A', e);
      added[e.snapshot.key!] = _value(e);
      place(e);
    });
    query.onChildChanged.listen((DatabaseEvent e) {
      record('C', e);
      changed[e.snapshot.key!] = _value(e);
    });
    query.onChildMoved.listen((DatabaseEvent e) {
      record('M', e);
      place(e);
    });
    query.onChildRemoved.listen((DatabaseEvent e) {
      record('R', e);
      page.remove(e.snapshot.key);
    });
    h.settle();
    h.server.answerListen('notes', null, query: _wireQuery);
    h.settle();
  }

  final Harness h;
  final Duration skew;
  late final DatabaseReference notes = h.ref('notes');
  late final Query query = notes.orderByChild('createdAt').limitToLast(10);
  final Map<String, String> names = <String, String>{};
  final List<String> page = <String>[];

  /// The value of the last child-added and child-changed event of each key.
  final Map<String, Map<String, Object?>> added =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> changed =
      <String, Map<String, Object?>>{};

  /// The notes the server holds, as it resolved them.
  final Map<String, Map<String, Object?>> server =
      <String, Map<String, Object?>>{};

  String name(String? key) => key == null ? '-' : names[key] ?? key;

  static Map<String, Object?> _value(DatabaseEvent e) =>
      Map<String, Object?>.from(e.snapshot.value! as Map<Object?, Object?>);

  void place(DatabaseEvent e) {
    page.remove(e.snapshot.key);
    final int previous = page.indexOf(e.previousChildKey ?? '');
    page.insert(e.previousChildKey == null ? 0 : previous + 1, e.snapshot.key!);
  }

  void record(String tag, DatabaseEvent e) =>
      h.log.add('$tag(${name(e.snapshot.key)},${name(e.previousChildKey)})');

  /// Acknowledges the last write with the server's clock at now + [offset]; returns that time.
  int ack(String key, Map<String, Object?> written, Duration offset) {
    final DateTime at = DateTime.now().add(offset);
    h.server.serverTime = at;
    h.server.ackLastWrite();
    h.settle();
    server[key] = <String, Object?>{
      ...server[key] ?? <String, Object?>{},
      ...written,
      if (written.containsKey('createdAt'))
        'createdAt': at.millisecondsSinceEpoch,
    };
    return at.millisecondsSinceEpoch;
  }

  DatabaseReference _push(String label) {
    final DatabaseReference ref = notes.push();
    names[ref.key!] = label;
    h.log.add('push $label');
    ref.set(<String, Object?>{
      'text': label,
      'createdAt': ServerValue.timestamp,
    });
    return ref;
  }

  void pushNote(String label) {
    final DatabaseReference ref = _push(label);
    // Before the ack the note may sort out of a full window: with the server ahead, the local estimate
    // is older than the notes already acknowledged.
    h.settle();
    h.elapse(const Duration(milliseconds: 20));
    ack(ref.key!, <String, Object?>{'text': label, 'createdAt': 0}, skew);
    expect(page.map(name), contains(label), reason: '${h.log}');
    h.elapse(const Duration(milliseconds: 20));
  }

  /// The page's first test: push, edit, ten pushes, ending with the ten pushes in the window.
  void tenPushes() {
    pushNote('hello');
    final String hello = names.keys.single;
    h.log.add('edit hello');
    notes.child(hello).update(<String, Object?>{'text': 'edited'});
    h.settle();
    ack(hello, <String, Object?>{'text': 'edited'}, skew);
    for (int i = 0; i < 10; i++) {
      pushNote('note $i');
    }
    expect(page.map(name), <String>[for (int i = 0; i < 10; i++) 'note $i']);
  }

  /// goOffline, then a push; returns its key.
  String pushOffline() {
    h.db.goOffline();
    h.settle();
    final String key = _push('written offline').key!;
    h.settle();
    h.elapse(const Duration(milliseconds: 20));
    return key;
  }

  /// goOnline; the server answers the listen sent again with its window, then acknowledges the queued
  /// write with its clock one second later than [skew] puts it. Returns the confirmed time.
  int goOnlineAndConfirm(Duration skew) {
    h.db.goOnline();
    h.elapse(const Duration(seconds: 1));
    final List<String> keys = server.keys.toList()
      ..sort((String a, String b) {
        final int byTime = (server[a]!['createdAt']! as int).compareTo(
          server[b]!['createdAt']! as int,
        );
        return byTime != 0 ? byTime : a.compareTo(b);
      });
    h.server.answerListen('notes', <String, Object?>{
      for (final String k in keys.skip(keys.length - 10)) k: server[k],
    }, query: _wireQuery);
    h.settle();
    final String key = names.entries
        .firstWhere(
          (MapEntry<String, String> e) => e.value == 'written offline',
        )
        .key;
    return ack(key, <String, Object?>{
      'text': 'written offline',
      'createdAt': 0,
    }, skew + const Duration(seconds: 1));
  }
}
