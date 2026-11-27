// Checks 27 to 41 of the production verification kit: 27 to 36 are the questions of the core side
// (rtdb/from_helper/reports/production_questions.md); 37 to 40 ask about priorities, 41 about a
// merge key that names the merge's own location. Each runs as an informational sequence. PASS
// means the sequence ran; the finding is the printed observation, which says whether it matched
// the expectation measured on the emulator. Exceptions: leaf B of check 30 (a refused write below
// a leaf, then its removal) is FAIL when the client does not end at the server's value, as check
// 23; with --expect-emptied-node-fix the transactions of check 38 are FAIL when one does not commit
// within two runs of its handler.
//
// Checks 28, 29, 33, 37, 38, 39 and 40 open a raw protocol connection of their own
// (RawConnection) with the throwaway user's ID token, to see frames the public API does not show;
// check 41 opens three (a writer and two listeners).
// It listens (in checks 38 and 39 also with a hash, in 39 with a compound hash), unlistens, gets
// (38 to 41), puts (39, some with a hash, 40 and 41) and merges (39, 41) and registers one
// onDisconnect write (check 33), all below the run's path. The auth request and its answer are
// never printed (an auth answer holds the token's claims); checks 38 to 41 print the answers of
// their other requests, which hold only the kit's own data.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:http/http.dart' as http;

import 'production_hashes.dart';
import 'verify_production.dart';

String _clip(Object? value, [int max = 200]) {
  final String text = value is String ? value : jsonEncode(value);
  return text.length <= max ? text : '${text.substring(0, max)}...';
}

String _yes(bool value) => value ? 'yes' : 'NO';

/// One frame pushed by the server to a [RawConnection], and when it arrived.
typedef Push = ({int ms, String action, String path, int? tag, Object? data});

/// A raw protocol connection (version 5) used to see the frames a listen receives. The socket is
/// kept, so that [destroy] can drop it without a WebSocket close.
class RawConnection {
  RawConnection._(this._socket, this._ws, this._runPath) {
    _ws.listen(_onMessage, onError: (Object _) {}, onDone: () {});
  }

  final Socket _socket;
  final WebSocket _ws;
  final String _runPath;
  final Stopwatch _clock = Stopwatch()..start();
  final Completer<Map<String, Object?>> _hello =
      Completer<Map<String, Object?>>();
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};
  int _request = 0;
  int _expected = 0;
  final StringBuffer _buffer = StringBuffer();

  /// Every push so far (`d`, `m`, `c` and others), in the order it arrived.
  final List<Push> pushes = <Push>[];

  /// Every request frame sent so far, as the JSON text that went on the wire.
  final List<String> sent = <String>[];

  /// Milliseconds since the connection opened (the clock of [frames]).
  int get elapsedMs => _clock.elapsedMilliseconds;

  /// Every assembled frame so far, answers and control frames included, as the server sent it.
  final List<({int ms, String text})> frames = <({int ms, String text})>[];

  /// Opens a connection to [kit]'s database, follows up to two resets and sends the user's token.
  static Future<RawConnection> open(Kit kit) async {
    final Backend backend = kit.backend;
    Uri url = backend.production
        ? Uri.parse('wss://${Uri.parse(backend.databaseUrl).host}/.ws')
        : Uri.parse('ws://${backend.emulatorHost}/.ws');
    url = url.replace(
      queryParameters: <String, String>{'v': '5', 'ns': backend.namespace},
    );
    for (int attempt = 0; attempt < 3; attempt++) {
      final RawConnection connection = await _connect(url, kit.runPath);
      kit.closers.add(connection.close);
      final Map<String, Object?> control = await within(
        connection._hello.future,
        'the hello of the raw connection',
      );
      if (control['t'] == 'h') {
        await connection._authenticate(kit);
        return connection;
      }
      await connection.close();
      url = url.replace(host: '${control['d']}');
    }
    throw StateError('the server reset the raw connection three times');
  }

  static Future<RawConnection> _connect(Uri url, String runPath) async {
    final HttpClient client = HttpClient();
    final math.Random random = math.Random.secure();
    final HttpClientRequest request = await within(
      client.getUrl(
        url.replace(scheme: url.scheme == 'wss' ? 'https' : 'http'),
      ),
      'the raw connection',
    );
    request
      ..followRedirects = false
      ..headers.set('Connection', 'Upgrade')
      ..headers.set('Upgrade', 'websocket')
      ..headers.set('Sec-WebSocket-Version', '13')
      ..headers.set(
        'Sec-WebSocket-Key',
        base64.encode(List<int>.generate(16, (_) => random.nextInt(256))),
      );
    final HttpClientResponse response = await within(
      request.close(),
      'the upgrade of the raw connection',
    );
    if (response.statusCode != 101) {
      throw StateError('the upgrade answered HTTP ${response.statusCode}');
    }
    final Socket socket = await response.detachSocket();
    client.close();
    return RawConnection._(
      socket,
      WebSocket.fromUpgradedSocket(socket, serverSide: false),
      runPath,
    );
  }

  Future<void> _authenticate(Kit kit) async {
    final String token = (await kit.auth!.getAccessToken(
      forceRefresh: false,
    )).token;
    final Map<String, Object?> answer = await request('auth', <String, Object?>{
      'cred': token,
    });
    if (answer['s'] != 'ok') {
      throw StateError(
        'the raw connection was not authenticated: ${answer['s']}',
      );
    }
  }

  void _onMessage(Object? message) {
    if (message is! String) {
      return;
    }
    if (_expected == 0 &&
        message.length <= 6 &&
        int.tryParse(message) != null) {
      _expected = int.parse(message);
      return;
    }
    if (_expected > 0) {
      _buffer.write(message);
      if (--_expected > 0) {
        return;
      }
      message = _buffer.toString();
      _buffer.clear();
    }
    frames.add((ms: _clock.elapsedMilliseconds, text: message));
    _onFrame(jsonDecode(message));
  }

  void _onFrame(Object? frame) {
    if (frame is! Map<String, Object?>) {
      return;
    }
    final Object? data = frame['d'];
    if (data is! Map<String, Object?>) {
      return;
    }
    if (frame['t'] == 'c') {
      final Object? type = data['t'];
      if ((type == 'h' || type == 'r') && !_hello.isCompleted) {
        _hello.complete(<String, Object?>{'t': type, 'd': data['d']});
      }
      return;
    }
    final Object? number = data['r'];
    if (number is int) {
      _pending
          .remove(number)
          ?.complete(
            (data['b'] as Map<String, Object?>?) ?? const <String, Object?>{},
          );
      return;
    }
    final Map<String, Object?> body =
        (data['b'] as Map<String, Object?>?) ?? const <String, Object?>{};
    final String full = '${body['p'] ?? ''}'.replaceFirst(RegExp('^/'), '');
    pushes.add((
      ms: _clock.elapsedMilliseconds,
      action: '${data['a']}',
      path: full.startsWith('$_runPath/')
          ? full.substring(_runPath.length + 1)
          : full,
      tag: body['t'] is int ? body['t']! as int : null,
      data: body['d'],
    ));
  }

  /// Sends one request and returns the body of its answer (`s` and `d`).
  Future<Map<String, Object?>> request(
    String action,
    Map<String, Object?> body,
  ) {
    final int number = ++_request;
    final Completer<Map<String, Object?>> answer =
        Completer<Map<String, Object?>>();
    _pending[number] = answer;
    final String text = jsonEncode(<String, Object?>{
      't': 'd',
      'd': <String, Object?>{'r': number, 'a': action, 'b': body},
    });
    sent.add(text);
    _ws.add(text);
    return within(answer.future, 'the answer to a raw "$action" request');
  }

  /// Listens to [relative] below the run's path with [query] and [tag] (no query: the default).
  Future<String> listen(
    String relative,
    Map<String, Object?> query,
    int? tag,
  ) async {
    final Map<String, Object?> answer = await request('q', <String, Object?>{
      'p': '/$_runPath/$relative',
      'h': '',
      'q': ?(query.isEmpty ? null : query),
      't': ?tag,
    });
    return '${answer['s']}';
  }

  /// Listens to [relative] below the run's path with the default query, no tag, [hash] and, when
  /// given, the compound hash [compound] (`ch`: `ps` and `hs`), and returns the whole answer (`s`
  /// and `d`; a listen answer holds only the kit's own data).
  Future<Map<String, Object?>> listenAnswer(
    String relative, {
    String hash = '',
    Map<String, Object?>? compound,
  }) => request('q', <String, Object?>{
    'p': '/$_runPath/$relative',
    'h': hash,
    'ch': ?compound,
  });

  /// Sends a put (`p`) of [data] at [relative] below the run's path, with [hash] when given (a
  /// transaction's put: the server refuses it as `datastale` unless its node has that hash), and
  /// returns the whole answer.
  Future<Map<String, Object?>> put(
    String relative,
    Object? data, {
    String? hash,
  }) => request('p', <String, Object?>{
    'p': '/$_runPath/$relative',
    'd': data,
    'h': ?hash,
  });

  /// Sends a merge (`m`, an update) of [data] at [relative] below the run's path and returns the
  /// whole answer.
  Future<Map<String, Object?>> merge(
    String relative,
    Map<String, Object?> data,
  ) => request('m', <String, Object?>{'p': '/$_runPath/$relative', 'd': data});

  /// Sends a `g` (get) request for [relative] below the run's path with the default query and
  /// returns the whole answer (`s` and `d`, the data).
  Future<Map<String, Object?>> get(String relative) => request(
    'g',
    <String, Object?>{'p': '/$_runPath/$relative', 'q': <String, Object?>{}},
  );

  /// Ends the listen [listen] made.
  Future<void> unlisten(
    String relative,
    Map<String, Object?> query,
    int? tag,
  ) => request('n', <String, Object?>{
    'p': '/$_runPath/$relative',
    'q': ?(query.isEmpty ? null : query),
    't': ?tag,
  });

  /// Drops the TCP connection without a WebSocket close.
  void destroy() => _socket.destroy();

  /// Closes the connection.
  Future<void> close() async {
    try {
      await _ws.close().timeout(const Duration(seconds: 5));
    } on Object {
      _socket.destroy();
    }
  }
}

/// One push printed: action, path below the run, tag and data.
String describePush(Push push) =>
    '${push.action} ${push.path}${push.tag == null ? '' : ' t=${push.tag}'} '
    '${_clip(push.data, 160)}';

// -----------------------------------------------------------------------------------------------
// Line 1-3: priorities.

Future<CheckResult> _priorityQuestions(Kit kit) async {
  final KitDb a = kit.open();
  final DatabaseReference x = a.ref('pq/x');
  await within(
    x.set(<String, Object?>{'a': 1}, priority: 5),
    'set with priority 5',
  );
  await within(x.child('a').remove(), 'the removal of x/a');
  final DataSnapshot emptied = await within(
    kit.open().ref('pq/x').get(),
    'a fresh read of x',
  );
  final String exportEmptied = (await kit.rest(
    'GET',
    '${kit.runPath}/pq/x',
    query: const <String, String>{'format': 'export'},
  )).body;
  String missing;
  try {
    await within(
      a.ref('pq/missing').setPriority(1),
      'setPriority on a missing path',
    );
    final http.Response export = await kit.rest(
      'GET',
      '${kit.runPath}/pq/missing',
      query: const <String, String>{'format': 'export'},
    );
    missing = 'accepted; the path now holds ${export.body}';
  } on FirebaseDatabaseException catch (e) {
    missing = 'refused: code ${e.code}, serverStatus "${e.serverStatus}"';
  }
  final DatabaseReference leaf = a.ref('pq/leaf');
  await within(leaf.set('leaf'), 'the leaf');
  await within(leaf.setPriority(3), 'setPriority on the leaf');
  final String exportLeaf = (await kit.rest(
    'GET',
    '${kit.runPath}/pq/leaf',
    query: const <String, String>{'format': 'export'},
  )).body;
  final DataSnapshot leafRead = await within(
    kit.open().ref('pq/leaf').get(),
    'a fresh read of the leaf',
  );
  final bool line1 = emptied.value == null && emptied.priority == null;
  return CheckResult(
    Status.pass,
    'Line 1: a fresh client reads x as ${_clip(emptied.value)} with priority '
    '${emptied.priority} (expected null and none: ${_yes(line1)}); line 2: $missing; line 3: '
    'export $exportLeaf.',
    details: <String>[
      'line 1, export of x after the removal: $exportEmptied',
      'line 3, a fresh client reads the leaf: ${leafRead.value}, priority ${leafRead.priority}',
    ],
    observed: <String, Object?>{
      'line1Value': emptied.value,
      'line1Priority': emptied.priority,
      'line1Export': exportEmptied,
      'line2': missing,
      'line3Export': exportLeaf,
    },
  );
}

// -----------------------------------------------------------------------------------------------
// Lines 4-10 and the cheap extras: the frames a limit query receives.

/// One case of check 28.
typedef FrameCase = ({
  String id,
  String label,
  Map<String, Object?> query,
  Future<void> Function(DatabaseReference list) write,
});

const Map<String, Object?> _keyFirst2 = <String, Object?>{
  'i': '.key',
  'l': 2,
  'vf': 'l',
};

/// The cases of check 28, on the list a {n:1}, b {n:2}, c {n:3}, d {n:4}.
List<FrameCase> frameCases() => <FrameCase>[
  (
    id: '4',
    label: 'set at the query path',
    query: _keyFirst2,
    write: (DatabaseReference list) => list.set(<String, Object?>{
      for (final String k in <String>['a', 'b', 'c', 'd'])
        k: <String, Object?>{'n': 10 * ('abcd'.indexOf(k) + 1)},
    }),
  ),
  (
    id: '5',
    label: 'update at the query path, same members',
    query: _keyFirst2,
    write: (DatabaseReference list) => list.update(<String, Object?>{
      'a': <String, Object?>{'n': 11},
    }),
  ),
  (
    id: '6',
    label: 'update at the query path, a leaves and c enters',
    query: _keyFirst2,
    write: (DatabaseReference list) => list.update(<String, Object?>{
      'a': null,
      'c': <String, Object?>{'n': 33},
    }),
  ),
  (
    id: '7',
    label: 'set below a child inside the window (a/n)',
    query: _keyFirst2,
    write: (DatabaseReference list) => list.child('a/n').set(5),
  ),
  (
    id: '8',
    label: 'set below a child outside the window (d/n)',
    query: _keyFirst2,
    write: (DatabaseReference list) => list.child('d/n').set(9),
  ),
  (
    id: '9',
    label: 'remove of a child inside the window (a)',
    query: _keyFirst2,
    write: (DatabaseReference list) => list.child('a').remove(),
  ),
  (
    id: '10',
    label: 'a new child that sorts into the window (aa)',
    query: _keyFirst2,
    write: (DatabaseReference list) =>
        list.child('aa').set(<String, Object?>{'n': 0}),
  ),
  (
    id: 'last',
    label: 'limitToLast(2), set below d inside the window',
    query: const <String, Object?>{'i': '.key', 'l': 2, 'vf': 'r'},
    write: (DatabaseReference list) => list.child('d/n').set(9),
  ),
  (
    id: 'priority',
    label:
        'ordered by priority, limitToFirst(2) (window d, c); a gets priority 0',
    query: const <String, Object?>{'l': 2, 'vf': 'l'},
    write: (DatabaseReference list) => list.child('a').setPriority(0),
  ),
  (
    id: 'mixed',
    label: 'update inside (a/n) and outside (d/n) the window',
    query: _keyFirst2,
    write: (DatabaseReference list) =>
        list.update(<String, Object?>{'a/n': 7, 'd/n': 8}),
  ),
  (
    id: 'alone',
    label:
        'update a/n alone (below one window child, no key outside the window)',
    query: _keyFirst2,
    write: (DatabaseReference list) => list.update(<String, Object?>{'a/n': 7}),
  ),
];

/// The list of four children each case starts from, with priorities d 1, c 2, b 3, a 4.
Map<String, Object?> _baseList() => <String, Object?>{
  for (final String k in <String>['a', 'b', 'c', 'd'])
    k: <String, Object?>{
      'n': 'abcd'.indexOf(k) + 1,
      '.priority': 4 - 'abcd'.indexOf(k),
    },
};

/// How long a raw listener collects frames after a write.
const Duration _settle = Duration(milliseconds: 1500);

Future<List<String>> _runFrameCase(
  Kit kit,
  RawConnection raw,
  KitDb writer,
  FrameCase c,
  int tag,
) async {
  final String path = 'frames/q${c.id}';
  final http.Response base = await kit.rest(
    'PUT',
    '${kit.runPath}/$path',
    body: _baseList(),
  );
  if (base.statusCode != 200) {
    throw StateError('the base list answered HTTP ${base.statusCode}');
  }
  final int before = raw.pushes.length;
  final String status = await raw.listen(path, c.query, tag);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final List<String> initial = raw.pushes
      .skip(before)
      .map(describePush)
      .toList();
  final int mark = raw.pushes.length;
  await within(c.write(writer.ref(path)), 'the write of case ${c.id}');
  await Future<void>.delayed(_settle);
  final List<String> after = raw.pushes.skip(mark).map(describePush).toList();
  await raw.unlisten(path, c.query, tag);
  return <String>[
    'line ${c.id}: ${c.label}; listen ${jsonEncode(c.query)} answered $status',
    '  initial: ${initial.isEmpty ? 'no frame' : initial.join(' | ')}',
    '  after the write: ${after.isEmpty ? 'NO FRAME' : after.join(' | ')}',
  ];
}

Future<CheckResult> _limitFrames(Kit kit) async {
  final RawConnection raw = await RawConnection.open(kit);
  final KitDb writer = kit.open();
  final List<String> details = <String>[];
  final Map<String, Object?> observed = <String, Object?>{};
  int tag = 1;
  for (final FrameCase c in frameCases()) {
    final List<String> lines = await _runFrameCase(kit, raw, writer, c, tag++);
    details.addAll(lines);
    observed[c.id] = lines.last.substring('  after the write: '.length);
  }
  return CheckResult(
    Status.pass,
    'Frames of a limit query, seen on a raw connection, for lines 4 to 10 and four extras; '
    'compare each with the expectation in production_questions.md.',
    details: details,
    observed: observed,
  );
}

// -----------------------------------------------------------------------------------------------
// Line 11: the tagged frame and the untagged one.

Future<CheckResult> _taggedFirst(Kit kit) async {
  final RawConnection raw = await RawConnection.open(kit);
  final KitDb writer = kit.open();
  const String path = 'frames/q11';
  final http.Response base = await kit.rest(
    'PUT',
    '${kit.runPath}/$path',
    body: _baseList(),
  );
  if (base.statusCode != 200) {
    throw StateError('the base list answered HTTP ${base.statusCode}');
  }
  await raw.listen(path, _keyFirst2, 50);
  await raw.listen(path, const <String, Object?>{}, null);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final List<String> orders = <String>[];
  for (int i = 0; i < 5; i++) {
    final int mark = raw.pushes.length;
    await within(writer.ref('$path/a/n').set(100 + i), 'write $i');
    await Future<void>.delayed(_settle);
    final List<Push> got = raw.pushes.skip(mark).toList();
    orders.add(
      got.map((Push p) => p.tag == null ? 'untagged' : 'tagged').join(' then '),
    );
  }
  final int taggedFirst = orders
      .where((String o) => o.startsWith('tagged then'))
      .length;
  return CheckResult(
    Status.pass,
    'Line 11: with a tagged limit listen and a default listen on one path, the tagged frame came '
    'first in $taggedFirst of 5 writes (expected 5).',
    details: <String>[
      for (int i = 0; i < orders.length; i++) 'write $i: ${orders[i]}',
    ],
    observed: <String, Object?>{'taggedFirst': taggedFirst, 'orders': orders},
  );
}

// -----------------------------------------------------------------------------------------------
// Lines 12-14: a write below a leaf.

Future<List<Object?>> _settled(Recorder<DatabaseEvent> recorder) async {
  await Future<void>.delayed(const Duration(milliseconds: 800));
  return valuesOf(recorder);
}

Future<CheckResult> _belowLeaf(Kit kit) async {
  final KitDb a = kit.open();
  final DatabaseReference online = a.ref('leaf_online');
  final Recorder<DatabaseEvent> seen12 = Recorder<DatabaseEvent>(
    online.onValue,
  );
  await until(() => seen12.items.isNotEmpty, 'the first value event');
  await within(online.set('leaf'), 'the leaf');
  await within(online.child('a').set(1), 'the write below the leaf');
  final List<Object?> events12 = await _settled(seen12);
  final Object? server12 = await kit.open().read('leaf_online');

  final DatabaseReference ruled = a.ref('leaf_rule');
  final Recorder<DatabaseEvent> seen13 = Recorder<DatabaseEvent>(ruled.onValue);
  await until(() => seen13.items.isNotEmpty, 'the first value event');
  await within(ruled.set('leaf'), 'the leaf under the rule');
  final FirebaseDatabaseException? refused13 = await refusal(
    ruled.child('a').set(1),
    'the refused write below the leaf',
  );
  final List<Object?> events13 = await _settled(seen13);

  await within(ruled.set('leaf'), 'the leaf again');
  final int mark = seen13.items.length;
  final Future<FirebaseDatabaseException?> first = refusal(
    ruled.child('a').set(1),
    'the first write of line 14',
  );
  final Future<FirebaseDatabaseException?> second = refusal(
    ruled.child('b').set(2),
    'the second write of line 14',
  );
  handled(second);
  final FirebaseDatabaseException? refused14 = await first;
  final FirebaseDatabaseException? accepted14 = await second;
  final List<Object?> events14 = (await _settled(seen13)).skip(mark).toList();
  final Object? server14 = await kit.open().read('leaf_rule');
  final _LeafB b = await _leafB(kit);
  final _LeafRow end = b.rows.last;
  return CheckResult(
    _leafBStatus(b),
    'Line 12: server ${_clip(server12)}, client ${_clip(events12.last)} (expected {a:1} on both); '
    'line 13: ${outcome(refused13)}, client ends at ${_clip(events13.last)} (expected leaf); '
    'line 14: client ${_clip(events14.isEmpty ? 'no event' : events14.last)}, server '
    '${_clip(server14)} (expected equal); leaf B: ${_leafBLine(b)}.',
    details: <String>[
      'line 12 events: ${events12.map(_clip).join(', ')}',
      'line 13 events: ${events13.map(_clip).join(', ')}',
      'line 14: first write ${outcome(refused14)}, second ${outcome(accepted14)}; events '
          '${events14.map(_clip).join(', ')}',
      'leaf B: server 1 (REST), set(leaf_rule/a, 1) ${outcome(b.refused)}, set(leaf_rule/a, '
          'null) ${outcome(b.removed)}',
      for (final _LeafRow row in b.rows)
        'leaf B +${row.at ~/ 1000} s: server ${_clip(row.server)} | listener last '
            '${_clip(row.listener)} | get() ${_clip(row.own)} | fresh client '
            '${_clip(row.fresh)} -> ${row.same ? 'SAME' : 'DIFFERS'}',
      'leaf B listener values in order: ${b.events.map(_clip).join(', ')}',
    ],
    observed: <String, Object?>{
      'server12': server12,
      'client12': events12.last,
      'code13': refused13?.code,
      'client13': events13.last,
      'client14': events14.isEmpty ? null : events14.last,
      'server14': server14,
      'codeB': b.refused?.code,
      'removedB': b.removed?.code,
      'eventsB': b.events,
      'serverB': end.server,
      'listenerB': end.listener,
      'getB': end.own,
      'freshB': end.fresh,
    },
  );
}

/// Leaf B decides check 30, as check 23 does for the offline form: FAIL when the writer's
/// listener, its get() or a fresh client differ from the server at the last checkpoint;
/// INCONCLUSIVE when the rule did not refuse the first write.
Status _leafBStatus(_LeafB b) => b.refused == null
    ? Status.inconclusive
    : b.rows.last.same
    ? Status.pass
    : Status.fail;

/// The summary of leaf B.
String _leafBLine(_LeafB b) {
  final _LeafRow end = b.rows.last;
  if (b.refused == null) {
    return 'the rule did not refuse set(leaf_rule/a, 1), so the sequence did not run as designed';
  }
  if (end.same) {
    return 'the listener, get() and a fresh client end at the server value ${_clip(end.server)}';
  }
  return 'DIFFERS at +${end.at ~/ 1000} s: server ${_clip(end.server)}, listener '
      '${_clip(end.listener)}, get() ${_clip(end.own)}, fresh client ${_clip(end.fresh)}';
}

/// One checkpoint of leaf B: the server's value over REST, the writer's last listener value, its
/// get() and a fresh client's get(), `at` milliseconds after both writes settled.
typedef _LeafRow = ({
  int at,
  Object? server,
  Object? listener,
  Object? own,
  Object? fresh,
  bool same,
});

/// What leaf B observed: how each write ended, the listener values and the checkpoints.
typedef _LeafB = ({
  FirebaseDatabaseException? refused,
  FirebaseDatabaseException? removed,
  List<Object?> events,
  List<_LeafRow> rows,
});

/// Leaf B, the sequence of the JS leg (`js_leg.mjs`, `formLeafB`): the server holds 1 at
/// `leaf_rule` (REST); a new client listens there, then sets `leaf_rule/a` to 1 (refused by the
/// `.validate false` rule) and to null without waiting for the first; at +0 and +5 s after both
/// settled it compares its listener and get(), and a fresh client, with the server.
Future<_LeafB> _leafB(Kit kit) async {
  final http.Response base = await kit.rest(
    'PUT',
    '${kit.runPath}/leaf_rule',
    body: 1,
  );
  if (base.statusCode != 200) {
    throw StateError(
      'the value 1 at leaf_rule answered HTTP ${base.statusCode}',
    );
  }
  final KitDb w = kit.open();
  final DatabaseReference r = w.ref('leaf_rule');
  final Recorder<DatabaseEvent> seen = Recorder<DatabaseEvent>(r.onValue);
  await until(() => seen.items.isNotEmpty, 'the first value event of leaf B');
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  final Future<FirebaseDatabaseException?> first = refusal(
    r.child('a').set(1),
    'set(leaf_rule/a, 1) of leaf B',
  );
  final Future<FirebaseDatabaseException?> second = refusal(
    r.child('a').set(null),
    'set(leaf_rule/a, null) of leaf B',
  );
  handled(second);
  final FirebaseDatabaseException? refused = await first;
  final FirebaseDatabaseException? removed = await second;
  final Stopwatch since = Stopwatch()..start();
  final KitDb reader = kit.open();
  final List<_LeafRow> rows = <_LeafRow>[];
  for (final int at in checkpointsMs) {
    await reach(since, at);
    final http.Response server = await kit.rest(
      'GET',
      '${kit.runPath}/leaf_rule',
    );
    if (server.statusCode != 200) {
      throw StateError(
        'the REST read of leaf_rule answered HTTP ${server.statusCode}',
      );
    }
    final Object? value = jsonDecode(server.body);
    final Object? listener = valuesOf(seen).last;
    final Object? own = (await within(
      r.get(),
      'get() by the writer of leaf B',
    )).value;
    final Object? fresh = await reader.read('leaf_rule');
    final String expected = jsonEncode(value);
    rows.add((
      at: at,
      server: value,
      listener: listener,
      own: own,
      fresh: fresh,
      same:
          jsonEncode(listener) == expected &&
          jsonEncode(own) == expected &&
          jsonEncode(fresh) == expected,
    ));
  }
  return (
    refused: refused,
    removed: removed,
    events: valuesOf(seen),
    rows: rows,
  );
}

// -----------------------------------------------------------------------------------------------
// Lines 15-19: transactions.

Future<String> _contention(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  final List<Recorder<DatabaseEvent>> seen = <Recorder<DatabaseEvent>>[
    Recorder<DatabaseEvent>(a.ref('tq/count').onValue),
    Recorder<DatabaseEvent>(b.ref('tq/count').onValue),
  ];
  int committed = 0;
  final Map<String, int> failures = <String, int>{};
  Future<void> loop(KitDb db) async {
    for (int i = 0; i < 50; i++) {
      try {
        final TransactionResult result = await within(
          db
              .ref('tq/count')
              .runTransaction(
                (Object? c) => Transaction.success(((c as num?) ?? 0) + 1),
              ),
          'transaction $i',
        );
        committed += result.committed ? 1 : 0;
      } on FirebaseDatabaseException catch (e) {
        failures[e.code] = (failures[e.code] ?? 0) + 1;
      }
    }
  }

  await Future.wait(<Future<void>>[loop(a), loop(b)]);
  await Future<void>.delayed(const Duration(seconds: 1));
  final Object? last = await kit.open().read('tq/count');
  int decreases = 0;
  for (final Recorder<DatabaseEvent> recorder in seen) {
    num highest = 0;
    for (final Object? value in valuesOf(recorder)) {
      if (value is num && value < highest) {
        decreases++;
      }
      highest = value is num ? math.max(highest, value) : highest;
    }
  }
  return 'line 15: final $last (expected 100), $committed of 100 committed, failed: '
      '${failures.isEmpty ? 'none' : failures}, $decreases value events lower than an earlier '
      'one (expected 0)';
}

int _puts(KitDb db) =>
    db.log.lines.where((String line) => line == 'debug: send p').length;

Future<String> _refusedTransaction(Kit kit) async {
  final KitDb a = kit.open();
  final int puts = _puts(a);
  try {
    await within(
      a.db
          .ref(kit.deniedPath)
          .runTransaction((Object? c) => Transaction.success(1)),
      'the refused transaction',
    );
    await within(
      a.db.ref(kit.deniedPath).remove(),
      'the removal at the refused path',
    );
    return 'line 16: COMMITTED at a refused path (removed again)';
  } on FirebaseDatabaseException catch (e) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return 'line 16: ${describe(e)}, ${_puts(a) - puts} put frames sent '
        '(expected 1)';
  }
}

Future<String> _overriddenTransaction(Kit kit) async {
  final KitDb a = kit.open();
  await a.connected();
  final Future<TransactionResult> transaction = a
      .ref('tq/over')
      .runTransaction((Object? c) => Transaction.success(1));
  final Future<void> set = a.ref('tq/over').set(99);
  handled(set);
  String result;
  try {
    final TransactionResult r = await within(
      transaction,
      'the overridden transaction',
    );
    result = 'completed, committed ${r.committed}';
  } on FirebaseDatabaseException catch (e) {
    result = 'failed with ${e.code}';
  }
  await within(set, 'the set');
  final Object? server = await kit.open().read('tq/over');
  return 'line 17: the transaction $result (expected overridden-by-set), server $server '
      '(expected 99)';
}

Future<String> _offlineTransaction(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  await a.connected();
  a.db.goOffline();
  await a.disconnected();
  await within(b.ref('tq/offline').set(5), 'the write of the second client');
  final List<Object?> seen = <Object?>[];
  final Future<TransactionResult> transaction = a
      .ref('tq/offline')
      .runTransaction((Object? c) {
        seen.add(c);
        return Transaction.success(((c as num?) ?? 0) + 1);
      });
  a.db.goOnline();
  final TransactionResult result = await within(
    transaction,
    'the offline transaction',
  );
  return 'line 18: committed ${result.committed} with ${result.snapshot.value}; the handler '
      'saw ${seen.join(', ')} (${seen.length} runs; the first offline run sees no data)';
}

Future<String> _maxRetries(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  await within(b.ref('tq/busy').set(0), 'the start value');
  int runs = 0;
  try {
    final TransactionResult result = await within(
      a.ref('tq/busy').runTransaction((Object? c) {
        runs++;
        unawaited(b.ref('tq/busy').set(1000 + runs).catchError((Object _) {}));
        return Transaction.success(-runs);
      }),
      'the contended transaction',
      const Duration(seconds: 60),
    );
    return 'line 19: committed ${result.committed} after $runs runs (expected max-retries '
        'after 25; the rival writes race the transaction, so this is not forced)';
  } on FirebaseDatabaseException catch (e) {
    return 'line 19: ${e.code} after $runs runs (expected max-retries after 25)';
  }
}

Future<CheckResult> _transactionQuestions(Kit kit) async {
  final List<String> lines = <String>[];
  for (final Future<String> Function(Kit) question
      in <Future<String> Function(Kit)>[
        _contention,
        _refusedTransaction,
        _overriddenTransaction,
        _offlineTransaction,
        _maxRetries,
      ]) {
    lines.add(await question(kit));
    await kit.closeOpen();
  }
  return CheckResult(
    Status.pass,
    'Lines 15 to 19 ran; the findings are below.',
    details: lines,
    observed: <String, Object?>{'lines': lines},
  );
}

// -----------------------------------------------------------------------------------------------
// Line 23: a large child and a small listener.

Future<CheckResult> _largeChild(Kit kit) async {
  final KitDb writer = kit.open();
  await within(
    writer.ref('large/blob').set('x' * 1000000),
    'the 1 MB value',
    checkWait,
  );
  final KitDb c = kit.open();
  final Recorder<DatabaseEvent> small = Recorder<DatabaseEvent>(
    c.ref('large_small').onValue,
  );
  await until(() => small.items.isNotEmpty, 'the small listener');
  final Stopwatch watch = Stopwatch()..start();
  int? smallMs;
  final Future<DataSnapshot> big = c.ref('large/blob').get();
  handled(big);
  await within(writer.ref('large_small').set('ping'), 'the small write');
  final Future<void> smallSeen = until(
    () => valuesOf(small).contains('ping'),
    'the small event',
  ).then((_) => smallMs = watch.elapsedMilliseconds);
  handled(smallSeen);
  final DataSnapshot blob = await within(
    big,
    'get() of the 1 MB value',
    checkWait,
  );
  final int bigMs = watch.elapsedMilliseconds;
  await smallSeen;
  return CheckResult(
    Status.pass,
    'Line 23: get() of 1 MB took $bigMs ms; the small sibling\'s event came at $smallMs ms '
    '(${smallMs! < bigMs ? 'before' : 'after'} the large value).',
    observed: <String, Object?>{
      'bigMs': bigMs,
      'smallMs': smallMs,
      'bigLength': (blob.value as String?)?.length,
    },
  );
}

// -----------------------------------------------------------------------------------------------
// Line 24: onDisconnect after a dropped socket.

Future<CheckResult> _droppedSocket(Kit kit) async {
  final RawConnection raw = await RawConnection.open(kit);
  final KitDb observer = kit.open();
  final Map<String, Object?> answer = await raw.request('o', <String, Object?>{
    'p': '/${kit.runPath}/dropped',
    'd': 'gone',
  });
  if (answer['s'] != 'ok') {
    return CheckResult(
      Status.fail,
      'The onDisconnect write was refused: ${answer['s']}',
    );
  }
  final Recorder<DatabaseEvent> seen = Recorder<DatabaseEvent>(
    observer.ref('dropped').onValue,
  );
  await until(() => seen.items.isNotEmpty, 'the observer');
  final Stopwatch watch = Stopwatch()..start();
  raw.destroy();
  const Duration limit = Duration(seconds: 150);
  try {
    await until(
      () => valuesOf(seen).contains('gone'),
      'the onDisconnect write',
      limit,
    );
  } on KitTimeout {
    kit.lateWritesPossible = true;
    return CheckResult(
      Status.inconclusive,
      'Line 24: the onDisconnect write had not run ${limit.inSeconds} s after the socket was '
      'dropped without a close.',
    );
  }
  return CheckResult(
    Status.pass,
    'Line 24: the onDisconnect write ran ${watch.elapsedMilliseconds} ms after the socket was '
    'dropped without a close (the emulator: at once).',
    observed: <String, Object?>{'afterDropMs': watch.elapsedMilliseconds},
  );
}

// -----------------------------------------------------------------------------------------------
// Line 26: pipelined increments from two clients.

Future<CheckResult> _pipelinedIncrements(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  await Future.wait(<Future<void>>[a.connected(), b.connected()]);
  final Stopwatch watch = Stopwatch()..start();
  await within(
    Future.wait(<Future<void>>[
      for (int i = 0; i < 100; i++) ...<Future<void>>[
        a.ref('pipelined_increments').set(ServerValue.increment(1)),
        b.ref('pipelined_increments').set(ServerValue.increment(1)),
      ],
    ]),
    'the acknowledgement of 200 increments',
    checkWait,
  );
  final Object? value = await kit.open().read('pipelined_increments');
  return CheckResult(
    Status.pass,
    'Line 26: 200 increments from two clients without waiting gave $value (expected 200) in '
    '${watch.elapsedMilliseconds} ms.',
    observed: <String, Object?>{'value': value},
  );
}

// -----------------------------------------------------------------------------------------------
// Line 28: the server's limits, over REST.

Future<CheckResult> _serverLimits(Kit kit) async {
  final int extra = 33 - kit.runPath.split('/').length;
  final String deep = <String>[
    kit.runPath,
    for (int i = 0; i < extra; i++) 'd',
  ].join('/');
  final http.Response rest = await kit.rest('PUT', deep, body: 1);
  String client;
  try {
    await kit.open().db.ref(deep).set(1);
    client = 'accepted';
  } on ArgumentError catch (e) {
    client = 'refused before sending (${_clip('${e.message}', 100)})';
  } on FirebaseDatabaseException catch (e) {
    client = 'refused by the server: ${describe(e)}';
  }
  return CheckResult(
    Status.pass,
    'Line 28: a path of depth 33 over REST answered HTTP ${rest.statusCode} '
    '${_clip(rest.body, 160)}; the client: $client. The 16 MB write is not tried: the kit '
    'keeps its writes near 1 MB in total.',
    observed: <String, Object?>{
      'restStatus': rest.statusCode,
      'client': client,
    },
  );
}

// -----------------------------------------------------------------------------------------------
// Line 29: pipelined updates.

Future<CheckResult> _pipelinedUpdates(Kit kit) async {
  final KitDb a = kit.open();
  await a.connected();
  final DatabaseReference ref = a.ref('pipelined_updates');
  final Recorder<DatabaseEvent> seen = Recorder<DatabaseEvent>(ref.onValue);
  await until(() => seen.items.isNotEmpty, 'the first value event');
  final List<int> acks = <int>[];
  final Stopwatch watch = Stopwatch()..start();
  await within(
    Future.wait(<Future<void>>[
      for (int i = 0; i < 1000; i++)
        ref.update(<String, Object?>{'v': i}).then((_) => acks.add(i)),
    ]),
    'the acknowledgement of 1,000 updates',
    checkWait,
  );
  final int ms = watch.elapsedMilliseconds;
  final bool inOrder = <int>[
    for (int i = 1; i < acks.length; i++) i,
  ].every((int i) => acks[i] > acks[i - 1]);
  int backwards = 0;
  num highest = -1;
  for (final Object? value in valuesOf(seen)) {
    final Object? v = value is Map<String, Object?> ? value['v'] : null;
    if (v is num && v < highest) {
      backwards++;
    }
    highest = v is num ? math.max(highest, v) : highest;
  }
  final Object? last = await kit.open().read('pipelined_updates/v');
  return CheckResult(
    Status.pass,
    'Line 29: 1,000 updates in $ms ms (${(1000000 / math.max(ms, 1)).round()} ops/s); acks in '
    'order: ${_yes(inOrder)}; final $last (expected 999); $backwards value events went back.',
    observed: <String, Object?>{
      'inOrder': inOrder,
      'last': last,
      'backwards': backwards,
    },
  );
}

// -----------------------------------------------------------------------------------------------
// A child moved into and out of a priority-ordered limit window.

Future<CheckResult> _priorityWindow(Kit kit) async {
  final RawConnection raw = await RawConnection.open(kit);
  final KitDb writer = kit.open();
  const String path = 'frames/priority_window';
  const Map<String, Object?> query = <String, Object?>{'l': 2, 'vf': 'l'};
  await kit.rest(
    'PUT',
    '${kit.runPath}/$path',
    body: <String, Object?>{
      for (int i = 1; i <= 4; i++)
        'c$i': <String, Object?>{'n': i, '.priority': i},
    },
  );
  final List<String> details = <String>[];
  final Map<String, Object?> observed = <String, Object?>{};
  final String status = await raw.listen(path, query, 60);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  observed['initial'] = raw.pushes.map(describePush).toList();
  details.add(
    'listen ${jsonEncode(query)} answered $status; initial: '
    '${(observed['initial']! as List<String>).join(' | ')}',
  );
  for (final (String step, int priority) in <(String, int)>[
    ('into', 0),
    ('outOf', 9),
  ]) {
    final int mark = raw.pushes.length;
    await within(
      writer.ref('$path/c4').setPriority(priority),
      'setPriority($priority) of c4',
    );
    await Future<void>.delayed(_settle);
    final List<String> frames = raw.pushes
        .skip(mark)
        .map(describePush)
        .toList();
    observed[step] = frames;
    details.add(
      'c4 priority $priority (moves ${step == 'into' ? 'into' : 'out of'} the window): '
      '${frames.isEmpty ? 'NO FRAME' : frames.join(' | ')}',
    );
  }
  await raw.unlisten(path, query, 60);
  return CheckResult(
    Status.pass,
    'Frames of orderByPriority().limitToFirst(2) over c1..c4 (priorities 1..4) while c4 '
    'moves into the window (priority 0) and out again (9).',
    details: details,
    observed: observed,
  );
}

// -----------------------------------------------------------------------------------------------
// Check 38: the priority of a node emptied by a write below it.

const Map<String, Object?> _noQuery = <String, Object?>{};

/// One push in full (no clipping): action, path below the run, tag and data.
String _verbatim(Push push) =>
    '${push.action} ${push.path}${push.tag == null ? '' : ' t=${push.tag}'} '
    '${jsonEncode(push.data)}';

/// The SHA-1 hash, base64, of [text], as the JS SDK hashes nodes (`sha1` in `@firebase/database`).
String _sha1(String text) =>
    base64.encode(sha1.convert(utf8.encode(text)).bytes);

/// [value] as the 16 lower-case hex digits of its IEEE 754 double (`doubleToIEEE754String`).
String _ieee754(num value) {
  final ByteData bytes = ByteData(8)..setFloat64(0, value.toDouble());
  return <String>[
    for (int i = 0; i < 8; i++)
      bytes.getUint8(i).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// The hash of a node with no children and the number priority [priority], formed as the JS SDK's
/// `ChildrenNode.hash` would if such a node existed there (the client never forms it: its empty
/// node has no priority).
String emptiedNodeHash(num priority) =>
    _sha1('priority:number:${_ieee754(priority)}:');

/// The hash of `{b: 1}` with no priority (`ChildrenNode.hash` over `LeafNode.hash`), the control
/// that shows whether the kit forms hashes the way the server does.
String controlNodeHash() => _sha1(':b:${_sha1('number:${_ieee754(1)}')}');

/// Sets [relative] to `{a: 1}` with priority 5 and removes `a`: the node is emptied by a write
/// below it.
Future<void> _emptyNode(KitDb a, String relative) async {
  await within(
    a.ref(relative).set(<String, Object?>{'a': 1}, priority: 5),
    'set of $relative with priority 5',
  );
  await within(
    a.ref(relative).child('a').remove(),
    'the removal of $relative/a',
  );
}

/// The REST export of [relative] below the run's path.
Future<String> _export(Kit kit, String relative) async => (await kit.rest(
  'GET',
  '${kit.runPath}/$relative',
  query: const <String, String>{'format': 'export'},
)).body;

/// How long the raw connection collects frames after a listen.
const Duration _listenSettle = Duration(milliseconds: 800);

/// (a) The raw listen answer, its frames and the raw get answer of the emptied node and of its
/// parent.
Future<List<String>> _emptiedFrames(
  Kit kit,
  KitDb a,
  RawConnection raw,
  Map<String, Object?> observed,
) async {
  await _emptyNode(a, 'emptied/p/n');
  final List<String> lines = <String>[];
  for (final (String id, String relative) in <(String, String)>[
    ('N', 'emptied/p/n'),
    ('P', 'emptied/p'),
  ]) {
    final int before = raw.pushes.length;
    final Map<String, Object?> answer = await raw.listenAnswer(relative);
    await Future<void>.delayed(_listenSettle);
    final List<String> frames = raw.pushes.skip(before).map(_verbatim).toList();
    await raw.unlisten(relative, _noQuery, null);
    final Map<String, Object?> got = await raw.get(relative);
    observed['aListen$id'] = jsonEncode(answer);
    observed['aFrames$id'] = frames;
    observed['aGet$id'] = jsonEncode(got);
    lines.addAll(<String>[
      '(a) $relative: listen answered ${jsonEncode(answer)}; frames: '
          '${frames.isEmpty ? 'NO FRAME' : frames.join(' | ')}',
      '(a) $relative: get answered ${jsonEncode(got)}',
    ]);
  }
  lines.add('(a) export of emptied/p: ${await _export(kit, 'emptied/p')}');
  return lines;
}

/// (b) One update that empties the node and writes `.priority`, and setPriority on an emptied
/// node: each one's outcome and the export after it.
Future<List<String>> _emptiedWrites(
  Kit kit,
  KitDb a,
  Map<String, Object?> observed,
) async {
  final DatabaseReference u = a.ref('emptied/b_update');
  await within(
    u.set(<String, Object?>{'a': 1}, priority: 5),
    'set of emptied/b_update with priority 5',
  );
  final String update = outcome(
    await refusal(
      u.update(<String, Object?>{'a': null, '.priority': 7}),
      'update {a: null, .priority: 7}',
    ),
  );
  final String updateExport = await _export(kit, 'emptied/b_update');
  await _emptyNode(a, 'emptied/b_set_priority');
  final String setPriority = outcome(
    await refusal(
      a.ref('emptied/b_set_priority').setPriority(9),
      'setPriority(9) on the emptied node',
    ),
  );
  final String setPriorityExport = await _export(kit, 'emptied/b_set_priority');
  observed.addAll(<String, Object?>{
    'bUpdate': update,
    'bUpdateExport': updateExport,
    'bSetPriority': setPriority,
    'bSetPriorityExport': setPriorityExport,
  });
  return <String>[
    '(b) {a:1} priority 5, then update {a: null, .priority: 7} in one call: $update; export '
        '$updateExport',
    '(b) emptied node (priority 5), then setPriority(9): $setPriority; export $setPriorityExport',
  ];
}

/// What a transaction did: how it ended, the values its handler saw (one per run) and whether
/// it committed.
typedef TransactionRuns = ({String result, List<Object?> seen, bool committed});

/// Whether a transaction committed within two runs of its handler: the first run may see a
/// client's cache (or nothing), the second sees the server's data.
bool withinTwoRuns(TransactionRuns t) => t.committed && t.seen.length <= 2;

/// Runs a transaction at [relative] on [client] that writes `{t: <run>}`.
Future<TransactionRuns> _transactionOn(
  KitDb client,
  String relative,
  String what,
) async {
  final List<Object?> seen = <Object?>[];
  try {
    final TransactionResult r = await within(
      client.ref(relative).runTransaction((Object? c) {
        seen.add(c);
        return Transaction.success(<String, Object?>{'t': seen.length});
      }),
      what,
    );
    return (
      result: r.committed ? 'committed' : 'not committed',
      seen: seen,
      committed: r.committed,
    );
  } on FirebaseDatabaseException catch (e) {
    return (result: 'failed: ${describe(e)}', seen: seen, committed: false);
  }
}

/// One line about [t]: how it ended, after how many runs, and the values seen.
String _runsLine(TransactionRuns t) =>
    '${t.result} after ${t.seen.length} runs of the handler (values seen: '
    '${t.seen.map(jsonEncode).join(', ')}); within 2 runs: ${_yes(withinTwoRuns(t))}';

/// (c) A transaction on an emptied node by a client with nothing cached (deciding: it must commit
/// within two runs), and raw listens with a hash: the emptied node's (priority 5, no children), a
/// control `{b: 1}` with its own hash and with a hash that does not match.
Future<List<String>> _emptiedHash(
  Kit kit,
  KitDb a,
  RawConnection raw,
  Map<String, Object?> observed,
) async {
  await _emptyNode(a, 'emptied/c_transaction');
  final KitDb fresh = kit.open();
  final TransactionRuns t = await _transactionOn(
    fresh,
    'emptied/c_transaction',
    'the transaction on the emptied node',
  );
  await fresh.db.close();
  final String transactionExport = await _export(kit, 'emptied/c_transaction');
  await _emptyNode(a, 'emptied/c_hash');
  await within(
    a.ref('emptied/c_control').set(<String, Object?>{'b': 1}),
    'the control {b: 1}',
  );
  final List<String> lines = <String>[
    '(c) transaction by a client with nothing cached: ${_runsLine(t)}; export '
        '$transactionExport',
  ];
  for (final (String id, String relative, String hash)
      in <(String, String, String)>[
        ('Hash', 'emptied/c_hash', emptiedNodeHash(5)),
        ('Control', 'emptied/c_control', controlNodeHash()),
        // A hash that does not match: the server must send the data, else NO FRAME above means
        // nothing.
        ('Wrong', 'emptied/c_control', emptiedNodeHash(6)),
      ]) {
    final int before = raw.pushes.length;
    final Map<String, Object?> answer = await raw.listenAnswer(
      relative,
      hash: hash,
    );
    await Future<void>.delayed(_listenSettle);
    final List<String> frames = raw.pushes.skip(before).map(_verbatim).toList();
    await raw.unlisten(relative, _noQuery, null);
    observed['c${id}Frames'] = frames;
    lines.add(
      '(c) listen $relative with hash $hash: answered ${jsonEncode(answer)}; data resent: '
      '${frames.isEmpty ? 'no (NO FRAME)' : 'yes: ${frames.join(' | ')}'}',
    );
  }
  observed.addAll(<String, Object?>{
    'cTransaction': t.result,
    'cRuns': t.seen.length,
    'cWithinTwoRuns': withinTwoRuns(t),
    'cTransactionExport': transactionExport,
  });
  return lines;
}

/// (d) The emptied node deleted, then a child written: does the priority come back?
Future<List<String>> _emptiedDeletion(
  Kit kit,
  KitDb a,
  Map<String, Object?> observed,
) async {
  const String d = 'emptied/d';
  await _emptyNode(a, d);
  final String emptied = await _export(kit, d);
  await within(a.ref(d).set(null), 'set(emptied/d, null)');
  final String deleted = await _export(kit, d);
  await within(a.ref('$d/b').set(1), 'set(emptied/d/b, 1)');
  final String refilled = await _export(kit, d);
  observed.addAll(<String, Object?>{
    'dEmptiedExport': emptied,
    'dDeletedExport': deleted,
    'dRefilledExport': refilled,
  });
  return <String>[
    '(d) export after emptying: $emptied; after set(n, null): $deleted; after set(n/b, 1): '
        '$refilled',
  ];
}

/// (e) The node of check 39's Q1 written by the client: `set(n, {a: 1})` with no priority, then
/// `update(n, {a: null, .priority: 7})`; a new client's transaction on it must commit within two
/// runs whether the server keeps n as `{.priority: 7}` or removes it.
Future<List<String>> _emptiedByUpdate(
  Kit kit,
  KitDb a,
  Map<String, Object?> observed,
) async {
  const String e = 'emptied/e_update';
  await within(a.ref(e).set(<String, Object?>{'a': 1}), 'set of $e');
  await within(
    a.ref(e).update(<String, Object?>{'a': null, '.priority': 7}),
    'update {a: null, .priority: 7} of $e',
  );
  final String before = await _export(kit, e);
  final KitDb fresh = kit.open();
  final TransactionRuns t = await _transactionOn(
    fresh,
    e,
    'the transaction on $e',
  );
  await fresh.db.close();
  final String after = await _export(kit, e);
  observed.addAll(<String, Object?>{
    'eExportBefore': before,
    'eTransaction': t.result,
    'eRuns': t.seen.length,
    'eWithinTwoRuns': withinTwoRuns(t),
    'eExportAfter': after,
  });
  return <String>[
    '(e) {a:1} without priority, update {a: null, .priority: 7} (export $before), then a '
        'transaction by a client with nothing cached: ${_runsLine(t)}; export $after',
  ];
}

/// (f) A restart on the SQLite cache: a client on one app with `sqlitePersistence` listens to n,
/// sets it to `{a: 1}` with priority 5 and empties it, and closes; a second client on the same
/// app and directory listens to n and runs a transaction there, which must commit within two
/// runs. The directory is a new temporary one, deleted at the end.
Future<List<String>> _emptiedRestart(
  Kit kit,
  Map<String, Object?> observed,
) async {
  const String f = 'emptied/f_restart';
  final Directory dir = await Directory.systemTemp.createTemp(
    'verify-database-kit-',
  );
  final FirebaseApp app = kit.signedInApp();
  KitDb? first;
  KitDb? second;
  try {
    first = kit.openOn(app, persistence: sqlitePersistence(dir.path));
    final Recorder<DatabaseEvent> seen1 = Recorder<DatabaseEvent>(
      first.ref(f).onValue,
    );
    await until(() => seen1.items.isNotEmpty, 'the first value event of $f');
    await _emptyNode(first, f);
    await Future<void>.delayed(_listenSettle);
    final bool durable1 = first.db.persistenceEnabled;
    await seen1.cancel();
    await within(first.db.close(), 'the close of the first SQLite client');
    second = kit.openOn(app, persistence: sqlitePersistence(dir.path));
    final Recorder<DatabaseEvent> seen2 = Recorder<DatabaseEvent>(
      second.ref(f).onValue,
    );
    await until(
      () => seen2.items.isNotEmpty,
      'the first value event after the restart',
    );
    final bool durable2 = second.db.persistenceEnabled;
    final TransactionRuns t = await _transactionOn(
      second,
      f,
      'the transaction after the restart',
    );
    await seen2.cancel();
    final String export = await _export(kit, f);
    observed.addAll(<String, Object?>{
      'fDurable': <bool>[durable1, durable2],
      'fTransaction': t.result,
      'fRuns': t.seen.length,
      'fWithinTwoRuns': withinTwoRuns(t),
      'fExport': export,
    });
    return <String>[
      '(f) SQLite cache: emptied with priority 5, closed, reopened on the same file (durable '
          'before ${_yes(durable1)}, after ${_yes(durable2)}), listened, then a transaction: '
          '${_runsLine(t)}; export $export',
    ];
  } finally {
    await first?.db.close();
    await second?.db.close();
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // A file still held: the temporary directory stays; it holds only this run's cache.
    }
  }
}

/// Whether the transactions of (c), (e) and (f) of check 38 each committed within two runs.
bool _emptiedCommitted(Map<String, Object?> observed) => <String>[
  'cWithinTwoRuns',
  'eWithinTwoRuns',
  'fWithinTwoRuns',
].every((String key) => observed[key] == true);

/// Check 38's verdict with [decide] (`--expect-emptied-node-fix`): FAIL when a transaction of
/// (c), (e) or (f) did not commit within two runs; INCONCLUSIVE when they did but (f) did not
/// reopen a durable cache (no restart was shown). Without [decide] PASS: informational.
Status _emptiedStatus(Map<String, Object?> observed, {required bool decide}) {
  if (!decide) {
    return Status.pass;
  }
  if (!_emptiedCommitted(observed)) {
    return Status.fail;
  }
  final List<Object?> durable = observed['fDurable']! as List<Object?>;
  return durable.every((Object? d) => d == true)
      ? Status.pass
      : Status.inconclusive;
}

/// The end of check 38's summary: the rule with `--expect-emptied-node-fix`, else what was seen.
String _emptiedVerdict(Kit kit, Map<String, Object?> observed) {
  if (kit.expectEmptiedNodeFix) {
    return '(c), (e) and (f) must commit within 2 runs';
  }
  return _emptiedCommitted(observed)
      ? 'informational (no --expect-emptied-node-fix): (c), (e) and (f) committed within 2 runs'
      : 'informational (no --expect-emptied-node-fix): (c), (e) or (f) did not commit within 2 '
            'runs; the client keeps the JS SDK\'s behaviour here, it drops the priority of an '
            'emptied node';
}

Future<CheckResult> _emptiedPriority(Kit kit) async {
  final RawConnection raw = await RawConnection.open(kit);
  final KitDb a = kit.open();
  final Map<String, Object?> observed = <String, Object?>{};
  final List<String> details = <String>[
    ...await _emptiedFrames(kit, a, raw, observed),
    ...await _emptiedWrites(kit, a, observed),
    ...await _emptiedHash(kit, a, raw, observed),
    ...await _emptiedDeletion(kit, a, observed),
    ...await _emptiedByUpdate(kit, a, observed),
    ...await _emptiedRestart(kit, observed),
  ];
  return CheckResult(
    _emptiedStatus(observed, decide: kit.expectEmptiedNodeFix),
    'A node with priority 5 emptied by a write below it: (a) listen and get frames, (b) an '
    'update writing .priority: ${observed['bUpdate']}, setPriority: ${observed['bSetPriority']}, '
    '(c) a transaction ${observed['cTransaction']} after ${observed['cRuns']} runs, (d) after '
    'set(n, null) and set(n/b, 1) the export is ${observed['dRefilledExport']}, (e) a '
    'transaction after update {a: null, .priority: 7} ${observed['eTransaction']} after '
    '${observed['eRuns']} runs, (f) a transaction after a SQLite restart '
    '${observed['fTransaction']} after ${observed['fRuns']} runs; '
    '${_emptiedVerdict(kit, observed)}. The frames and exports are below.',
    details: details,
    observed: observed,
  );
}

// -----------------------------------------------------------------------------------------------
// Check 39: what the server does with the priority of an emptied node, over raw frames only.

/// One request of check 39 at `relative` below the case's node ('' for the node itself): on the
/// raw connection `p` (put), `m` (merge) or `g` (get); `r` is a REST PUT as the user.
typedef RuleOp = ({String action, String relative, Object? data});

/// One case of check 39: `setup` runs before the listen, `ops` after it (all sent at once when
/// `pipelined`).
typedef RuleCase = ({
  String id,
  String label,
  List<RuleOp> setup,
  List<RuleOp> ops,
  bool pipelined,
});

RuleOp _put(String relative, Object? data) =>
    (action: 'p', relative: relative, data: data);

RuleOp _rest(String relative, Object? data) =>
    (action: 'r', relative: relative, data: data);

RuleOp _mergeOp(Map<String, Object?> data) =>
    (action: 'm', relative: '', data: data);

const RuleOp _getOp = (action: 'g', relative: '', data: null);

/// The cases of check 39, each at `<run>/server_rules/<id>`.
List<RuleCase> ruleCases() => <RuleCase>[
  (
    id: 'q1_a',
    label: 'Q1: n {a:1} (no priority), update {a:null, .priority:7}',
    setup: <RuleOp>[
      _put('', <String, Object?>{'a': 1}),
    ],
    ops: <RuleOp>[
      _mergeOp(<String, Object?>{'a': null, '.priority': 7}),
    ],
    pipelined: false,
  ),
  (
    id: 'q1_ab',
    label:
        'Q1: n {a:1, b:2} (no priority), update {a:null, b:null, .priority:7}',
    setup: <RuleOp>[
      _put('', <String, Object?>{'a': 1, 'b': 2}),
    ],
    ops: <RuleOp>[
      _mergeOp(<String, Object?>{'a': null, 'b': null, '.priority': 7}),
    ],
    pipelined: false,
  ),
  (
    id: 'q1_control',
    label: 'Q1 control: n {a:1} priority 5, update {a:null, .priority:7}',
    setup: <RuleOp>[
      _put('', <String, Object?>{'a': 1, '.priority': 5}),
    ],
    ops: <RuleOp>[
      _mergeOp(<String, Object?>{'a': null, '.priority': 7}),
    ],
    pipelined: false,
  ),
  (
    id: 'q2',
    label:
        'Q2: n {c: {x:1} priority 3} (n no priority), remove n/c/x, get, put n/.priority 9',
    setup: <RuleOp>[
      _put('', <String, Object?>{
        'c': <String, Object?>{'x': 1, '.priority': 3},
      }),
    ],
    ops: <RuleOp>[_put('c/x', null), _getOp, _put('.priority', 9)],
    pipelined: false,
  ),
  (
    id: 'q3_missing',
    label: 'Q3: put n {.priority:5} on a missing node',
    setup: const <RuleOp>[],
    ops: <RuleOp>[
      _put('', <String, Object?>{'.priority': 5}),
    ],
    pipelined: false,
  ),
  (
    id: 'q3_emptied',
    label: 'Q3: put n {.priority:8} on an emptied node that keeps priority 5',
    setup: <RuleOp>[
      _put('', <String, Object?>{'a': 1, '.priority': 5}),
      _put('a', null),
    ],
    ops: <RuleOp>[
      _put('', <String, Object?>{'.priority': 8}),
    ],
    pipelined: false,
  ),
  (
    id: 'q4',
    label:
        'Q4: n missing; put n/a 1, put n/.priority 7, put n/a null, sent without waiting',
    setup: const <RuleOp>[],
    ops: <RuleOp>[_put('a', 1), _put('.priority', 7), _put('a', null)],
    pipelined: true,
  ),
  (
    id: 'q6',
    label:
        'Q6: p {x: {a:1}} (x no priority), update at p {x/a: null, x/.priority: 3}',
    setup: <RuleOp>[
      _put('', <String, Object?>{
        'x': <String, Object?>{'a': 1},
      }),
    ],
    ops: <RuleOp>[
      _mergeOp(<String, Object?>{'x/a': null, 'x/.priority': 3}),
    ],
    pipelined: false,
  ),
  (
    id: 'q6_control',
    label:
        'Q6 control: p {x: {a:1} priority 5}, update at p {x/a: null, x/.priority: 3}',
    setup: <RuleOp>[
      _put('', <String, Object?>{
        'x': <String, Object?>{'a': 1, '.priority': 5},
      }),
    ],
    ops: <RuleOp>[
      _mergeOp(<String, Object?>{'x/a': null, 'x/.priority': 3}),
    ],
    pipelined: false,
  ),
  (
    id: 'q7_missing',
    label: 'Q7: REST PUT n {.priority:5} on a missing node',
    setup: const <RuleOp>[],
    ops: <RuleOp>[
      _rest('', <String, Object?>{'.priority': 5}),
    ],
    pipelined: false,
  ),
  (
    id: 'q7_parent',
    label: 'Q7: REST PUT of the parent {n: {.priority:5}, z: 1}',
    setup: const <RuleOp>[],
    ops: <RuleOp>[
      _rest('', <String, Object?>{
        'n': <String, Object?>{'.priority': 5},
        'z': 1,
      }),
    ],
    pipelined: false,
  ),
];

/// Sends [op] at [node] (below the run's path): over [raw], or for `r` as a REST PUT as the
/// user, whose answer is given as `s` (`HTTP <status>`) and `d` (the body).
Future<Map<String, Object?>> _sendRule(
  Kit kit,
  RawConnection raw,
  String node,
  RuleOp op,
) async {
  final String path = op.relative.isEmpty ? node : '$node/${op.relative}';
  try {
    if (op.action == 'r') {
      final http.Response r = await kit.rest(
        'PUT',
        '${kit.runPath}/$path',
        body: op.data,
      );
      return <String, Object?>{'s': 'HTTP ${r.statusCode}', 'd': r.body};
    }
    return await switch (op.action) {
      'p' => raw.put(path, op.data),
      'm' => raw.merge(path, op.data! as Map<String, Object?>),
      _ => raw.get(path),
    };
  } on KitTimeout catch (e) {
    throw KitTimeout('the answer to "${_describeOp(op)}" at $node', e.after);
  }
}

/// As [_sendRule], but a request the server does not answer within the step wait gives
/// `{"s": "NO ANSWER"}`: no answer is one of the outcomes check 39 reports.
Future<Map<String, Object?>> _answerOrNone(
  Kit kit,
  RawConnection raw,
  String node,
  RuleOp op,
) async {
  try {
    return await _sendRule(kit, raw, node, op);
  } on KitTimeout {
    return <String, Object?>{
      's': 'NO ANSWER',
      'd': 'none within ${stepWait.inSeconds} s',
    };
  }
}

String _describeOp(RuleOp op) => op.action == 'g'
    ? 'g n'
    : '${op.action == 'r' ? 'REST PUT' : op.action} n'
          '${op.relative.isEmpty ? '' : '/${op.relative}'} ${jsonEncode(op.data)}';

/// Offers transaction puts (a marker value) at [node] with the candidate hashes of [stored] (the
/// data a raw get answered): as stored, without the kept priorities, and `''`. Stops at the first
/// the server accepts. Returns the printed line and the name of the accepted candidate (null for
/// none).
Future<(String, String?)> _hashProbe(
  RawConnection raw,
  String node,
  Object? stored,
) async {
  final JsonNode? parsed = JsonNode.parse(stored);
  final Map<String, List<String>> names = <String, List<String>>{};
  for (final (String name, String hash) in <(String, String)>[
    ('as stored', simpleHash(parsed)),
    ('without kept priorities', simpleHash(withoutKeptPriorities(parsed))),
    ('empty', ''),
  ]) {
    (names[hash] ??= <String>[]).add(name);
  }
  final List<String> tries = <String>[];
  String? accepted;
  for (final MapEntry<String, List<String>> e in names.entries) {
    final Map<String, Object?> answer = await raw.put(node, <String, Object?>{
      'probe': 1,
    }, hash: e.key);
    final String name = e.value.join(' = ');
    tries.add("$name (${e.key.isEmpty ? "''" : e.key}): ${answer['s']}");
    if (answer['s'] == 'ok') {
      accepted = name;
      break;
    }
  }
  return (
    'transaction put with hash: ${tries.join('; ')} -> accepted: ${accepted ?? 'NONE'}',
    accepted,
  );
}

Future<List<String>> _runRuleCase(
  Kit kit,
  RawConnection raw,
  RuleCase c,
  Map<String, Object?> observed,
) async {
  final String node = 'server_rules/${c.id}';
  for (final RuleOp op in c.setup) {
    final Map<String, Object?> answer = await _sendRule(kit, raw, node, op);
    if (answer['s'] != 'ok') {
      throw StateError(
        'the setup "${_describeOp(op)}" of ${c.id} answered ${answer['s']}',
      );
    }
  }
  final int before = raw.pushes.length;
  final Map<String, Object?> listen = await raw.listenAnswer(node);
  await Future<void>.delayed(_listenSettle);
  final int mark = raw.pushes.length;
  final List<String> initial = raw.pushes
      .sublist(before, mark)
      .map(_verbatim)
      .toList();
  final List<Map<String, Object?>> answers = c.pipelined
      ? await Future.wait(<Future<Map<String, Object?>>>[
          for (final RuleOp op in c.ops) _answerOrNone(kit, raw, node, op),
        ])
      : <Map<String, Object?>>[
          for (final RuleOp op in c.ops)
            await _answerOrNone(kit, raw, node, op),
        ];
  await Future<void>.delayed(_listenSettle);
  final List<String> frames = raw.pushes.skip(mark).map(_verbatim).toList();
  await raw.unlisten(node, _noQuery, null);
  final Map<String, Object?> got = await raw.get(node);
  final String export = await _export(kit, node);
  final (String probe, String? accepted) = await _hashProbe(
    raw,
    node,
    got['d'],
  );
  observed[c.id] = <String, Object?>{
    'answers': <String>[
      for (final Map<String, Object?> a in answers) jsonEncode(a),
    ],
    'frames': frames,
    'get': jsonEncode(got),
    'export': export,
    'accepted': accepted,
  };
  return <String>[
    '${c.id}: ${c.label}',
    '  listen answered ${jsonEncode(listen)}; initial: '
        '${initial.isEmpty ? 'no frame' : initial.join(' | ')}',
    for (int i = 0; i < c.ops.length; i++)
      '  ${_describeOp(c.ops[i])} answered ${jsonEncode(answers[i])}',
    '  frames after: ${frames.isEmpty ? 'NO FRAME' : frames.join(' | ')}',
    '  get answered ${jsonEncode(got)}; export $export',
    '  $probe',
  ];
}

/// The data of Q5 at `<run>/server_rules/q5`: over 1 KB, a node `b` emptied between visible
/// siblings `a` and `c`, and a node `d/f` emptied inside a larger `d`.
Map<String, Object?> _q5Data() => <String, Object?>{
  'a': 'x' * 540,
  'b': <String, Object?>{'q': 1, '.priority': 5},
  'c': 'y' * 540,
  'd': <String, Object?>{
    'e': 'z' * 100,
    'f': <String, Object?>{'w': 1, '.priority': 2},
    'g': 'k' * 100,
  },
};

/// [json] with each string of Q5's filler (one character repeated, longer than 20) written as
/// `<540 x>`, so that the printed frames stay readable; everything else is as received.
Object? _abbreviated(Object? json) => switch (json) {
  final String text
      when text.length > 20 && text.split('').toSet().length == 1 =>
    '<${text.length} ${text[0]}>',
  final Map<String, Object?> map => <String, Object?>{
    for (final MapEntry<String, Object?> e in map.entries)
      e.key: _abbreviated(e.value),
  },
  final List<Object?> list => <Object?>[
    for (final Object? e in list) _abbreviated(e),
  ],
  _ => json,
};

/// One push of Q5, its data as [_abbreviated] gives it.
String _q5Push(Push push) =>
    '${push.action} ${push.path} ${jsonEncode(_abbreviated(push.data))}';

Map<String, Object?> _chJson(CompoundHashJson ch) => <String, Object?>{
  'ps': ch.posts,
  'hs': ch.hashes,
};

/// What a listen answer and its frames amount to: no data, a full `d`, or a range merge `rm`.
String _listenKind(List<Push> frames) {
  if (frames.isEmpty) {
    return 'ok with no data';
  }
  final Set<String> actions = <String>{for (final Push p in frames) p.action};
  if (actions.contains('rm')) {
    final bool empty = frames.every(
      (Push p) =>
          p.action != 'rm' ||
          (p.data is List<Object?> && (p.data! as List<Object?>).isEmpty),
    );
    return empty ? 'a range merge with no range (rm [])' : 'a range merge (rm)';
  }
  return actions.contains('d') ? 'a full d' : 'frames ${actions.join(', ')}';
}

/// Q5: listens with a compound hash formed without and with the kept priorities.
Future<List<String>> _compoundRanges(
  Kit kit,
  RawConnection raw,
  Map<String, Object?> observed,
) async {
  const String node = 'server_rules/q5';
  for (final RuleOp op in <RuleOp>[
    _put('', _q5Data()),
    _put('b/q', null),
    _put('d/f/w', null),
  ]) {
    final Map<String, Object?> answer = await _sendRule(kit, raw, node, op);
    if (answer['s'] != 'ok') {
      throw StateError(
        'the setup "${_describeOp(op)}" of q5 answered ${answer['s']}',
      );
    }
  }
  final Map<String, Object?> got = await raw.get(node);
  final JsonNode? stored = JsonNode.parse(got['d']);
  final String kept = simpleHash(stored);
  final String dropped = simpleHash(withoutKeptPriorities(stored));
  final CompoundHashJson without = compoundHash(
    stored,
    KeptPriorityRange.leftOut,
  );
  final CompoundHashJson stale = (
    posts: without.posts,
    hashes: <String>[
      for (final String h in without.hashes)
        h.isEmpty ? '' : sha1Base64Of('stale'),
    ],
  );
  final List<String> lines = <String>[
    'q5 (long filler strings written as <540 x>): get answered '
        '${jsonEncode(_abbreviated(got))}',
    '  simple hash as stored $kept, without kept priorities $dropped',
  ];
  for (final (String id, String label, String hash, CompoundHashJson ch)
      in <(String, String, String, CompoundHashJson)>[
        (
          'without',
          'h without, ch WITHOUT the kept priorities (the client)',
          dropped,
          without,
        ),
        (
          'withPriority',
          'h without, ch WITH them as a .priority leaf',
          dropped,
          compoundHash(stored, KeptPriorityRange.priorityLeaf),
        ),
        (
          'withEmpty',
          'h without, ch WITH them as an empty range "b":()',
          dropped,
          compoundHash(stored, KeptPriorityRange.emptyParens),
        ),
        (
          'stale',
          'control: h without, ch with every range wrong',
          dropped,
          stale,
        ),
        ('keptH', 'control: h as stored, ch WITHOUT', kept, without),
      ]) {
    final int before = raw.pushes.length;
    final Map<String, Object?> answer = await raw.listenAnswer(
      node,
      hash: hash,
      compound: _chJson(ch),
    );
    await Future<void>.delayed(_listenSettle);
    final List<Push> frames = raw.pushes.skip(before).toList();
    await raw.unlisten(node, _noQuery, null);
    final String kind = _listenKind(frames);
    observed['q5_$id'] = <String, Object?>{
      'answer': jsonEncode(answer),
      'kind': kind,
      'frames': frames.map(_q5Push).toList(),
    };
    lines.addAll(<String>[
      '  $label: ch ${jsonEncode(_chJson(ch))}',
      '    answered ${jsonEncode(answer)}: $kind; frames: '
          '${frames.isEmpty ? 'NO FRAME' : frames.map(_q5Push).join(' | ')}',
    ]);
  }
  return lines;
}

/// Sends the merge [data] at [name] below `server_rules/<group>` and reports it: the answer (or
/// `NO ANSWER` after the step wait), every frame received meanwhile (control frames verbatim,
/// with the ms since the merge was sent, as `+N ms`) and the REST export of [name]. With [fullWait] the
/// merge is watched for the whole step wait even when it is answered; otherwise an answered merge
/// is watched for [answeredWait] more.
Future<(List<String>, Map<String, Object?>)> _mergeReport(
  Kit kit,
  RawConnection raw,
  String group,
  String name,
  String label,
  Map<String, Object?> data, {
  bool fullWait = false,
  Duration answeredWait = const Duration(seconds: 1),
}) async {
  final String node = 'server_rules/$group';
  final int mark = raw.frames.length;
  final int sentAt = raw.elapsedMs;
  final int sentMark = raw.sent.length;
  final Stopwatch wait = Stopwatch()..start();
  final Map<String, Object?> answer = await _answerOrNone(kit, raw, node, (
    action: 'm',
    relative: name,
    data: data,
  ));
  final bool answered = answer['s'] != 'NO ANSWER';
  final Duration rest =
      (fullWait ? stepWait : (answered ? answeredWait : Duration.zero)) -
      wait.elapsed;
  if (rest > Duration.zero) {
    await Future<void>.delayed(rest);
  }
  final List<String> frames = <String>[
    for (final f in raw.frames.skip(mark)) '+${f.ms - sentAt} ms ${f.text}',
  ];
  final String export = await _export(kit, '$node/$name');
  return (
    <String>[
      '$label: merge at $group/$name',
      '  sent: ${raw.sent.skip(sentMark).join(' | ')}',
      '  answer: ${jsonEncode(answer)}',
      for (final String frame in frames) '  frame: $frame',
      if (frames.isEmpty) '  frame: NO FRAME',
      '  export of $name: $export',
    ],
    <String, Object?>{
      'answer': jsonEncode(answer),
      'frames': frames,
      'export': export,
    },
  );
}

/// Q8: a merge at a missing parent whose child value is only a priority, watched for 20 s, then
/// the same with a second child `y`, then an ordinary put on the same connection to show that it
/// still answers.
Future<List<String>> _priorityOnlyChild(
  Kit kit,
  RawConnection raw,
  Map<String, Object?> observed,
) async {
  final List<String> lines = <String>[
    'q8: parent missing, merge at parent {n: {.priority:5}} (and with y:1), 20 s each',
  ];
  final Map<String, Object?> seen = <String, Object?>{};
  for (final (String name, Map<String, Object?> data)
      in <(String, Map<String, Object?>)>[
        (
          'p1',
          <String, Object?>{
            'n': <String, Object?>{'.priority': 5},
          },
        ),
        (
          'p2',
          <String, Object?>{
            'n': <String, Object?>{'.priority': 5},
            'y': 1,
          },
        ),
      ]) {
    final (List<String> report, Map<String, Object?> one) = await _mergeReport(
      kit,
      raw,
      'q8',
      name,
      'q8 $name',
      data,
      fullWait: true,
    );
    seen[name] = one;
    lines.addAll(report);
  }
  lines.addAll(await _afterPut(kit, raw, 'q8', seen));
  observed['q8'] = seen;
  return lines;
}

/// One ordinary put at `server_rules/<group>/after`, to show that the connection still answers.
Future<List<String>> _afterPut(
  Kit kit,
  RawConnection raw,
  String group,
  Map<String, Object?> seen,
) async {
  final int mark = raw.frames.length;
  final int sentAt = raw.elapsedMs;
  final Map<String, Object?> after = await _answerOrNone(
    kit,
    raw,
    'server_rules/$group',
    _put('after', 1),
  );
  seen['after'] = jsonEncode(after);
  return <String>[
    '$group after: put $group/after 1 on the same connection',
    '  answer: ${jsonEncode(after)}',
    for (final f in raw.frames.skip(mark))
      '  frame: +${f.ms - sentAt} ms ${f.text}',
  ];
}

/// The merges of Q9: label, parent name and data. Each is sent at a fresh missing parent. (a) to
/// (g) hold a priority-only object somewhere, (f) and (g) in forms not measured before; (h) and
/// (i) are controls the server answers.
List<(String, String, Map<String, Object?>)> _q9Merges() =>
    <(String, String, Map<String, Object?>)>[
      (
        'q9a .value null + priority',
        'a',
        <String, Object?>{
          'n': <String, Object?>{'.value': null, '.priority': 5},
        },
      ),
      (
        'q9b priority + a null',
        'b',
        <String, Object?>{
          'n': <String, Object?>{'.priority': 5, 'a': null},
        },
      ),
      (
        'q9c a: priority only',
        'c',
        <String, Object?>{
          'n': <String, Object?>{
            'a': <String, Object?>{'.priority': 5},
          },
        },
      ),
      (
        'q9d multi-path key n/x',
        'd',
        <String, Object?>{
          'n/x': <String, Object?>{'.priority': 5},
        },
      ),
      (
        'q9e list form',
        'e',
        <String, Object?>{
          'n': <Object?>[
            <String, Object?>{'.priority': 5},
          ],
        },
      ),
      (
        'q9f .value {} + priority',
        'f',
        <String, Object?>{
          'n': <String, Object?>{'.value': <String, Object?>{}, '.priority': 5},
        },
      ),
      (
        'q9g priority + a []',
        'g',
        <String, Object?>{
          'n': <String, Object?>{'.priority': 5, 'a': <Object?>[]},
        },
      ),
      (
        'q9h control: n {a: {}}',
        'h',
        <String, Object?>{
          'n': <String, Object?>{'a': <String, Object?>{}},
        },
      ),
      (
        'q9i control: .value 1 + priority',
        'i',
        <String, Object?>{
          'n': <String, Object?>{'.value': 1, '.priority': 5},
        },
      ),
    ];

/// Q9: nine merges at fresh missing parents below `server_rules/q9`, each watched 20 s when the
/// server does not answer (1 s after an answer), then one ordinary put on the same connection.
Future<List<String>> _priorityOnlyForms(
  Kit kit,
  RawConnection raw,
  Map<String, Object?> observed,
) async {
  final List<String> lines = <String>[
    'q9: merges at fresh missing parents with a priority-only value in other forms',
  ];
  final Map<String, Object?> seen = <String, Object?>{};
  for (final (String label, String name, Map<String, Object?> data)
      in _q9Merges()) {
    final (List<String> report, Map<String, Object?> one) = await _mergeReport(
      kit,
      raw,
      'q9',
      name,
      label,
      data,
    );
    seen[name] = one;
    lines.addAll(report);
  }
  lines.addAll(await _afterPut(kit, raw, 'q9', seen));
  observed['q9'] = seen;
  return lines;
}

/// Q10: key order of a merge. Node `b` is put as `{x: {v: 1, .priority: 1}}` (no priority on `b`),
/// then one merge at `b` that removes `x` and sets the priority of `b`, with the keys in the order
/// written (the frame sent is printed verbatim), then a raw `g` and the REST export of `b`.
Future<List<String>> _mergeKeyOrder(
  Kit kit,
  RawConnection raw,
  Map<String, Object?> observed,
) async {
  final List<String> lines = <String>[
    'q10: b = {x: {v:1, .priority:1}} without priority on b, then one merge at b, keys in the order written',
  ];
  final Map<String, Object?> seen = <String, Object?>{};
  final List<(String, String, Map<String, Object?>)> orders =
      <(String, String, Map<String, Object?>)>[
        (
          'q10 order 1: .priority first',
          'o1',
          <String, Object?>{'.priority': 2, 'x/v': null, 'x/.priority': null},
        ),
        (
          'q10 order 2: .priority last',
          'o2',
          <String, Object?>{'x/v': null, 'x/.priority': null, '.priority': 2},
        ),
        (
          'q10 control: .priority 2 and x: null',
          'o3',
          <String, Object?>{'.priority': 2, 'x': null},
        ),
      ];
  for (final (String label, String name, Map<String, Object?> data) in orders) {
    final Map<String, Object?> setup = await _answerOrNone(
      kit,
      raw,
      'server_rules/q10',
      _put(name, <String, Object?>{
        'x': <String, Object?>{'v': 1, '.priority': 1},
      }),
    );
    final (List<String> report, Map<String, Object?> one) = await _mergeReport(
      kit,
      raw,
      'q10',
      name,
      label,
      data,
    );
    final Map<String, Object?> got = await raw.get('server_rules/q10/$name');
    one['setup'] = jsonEncode(setup);
    one['get'] = jsonEncode(got);
    seen[name] = one;
    lines
      ..add('  setup put $name answered ${jsonEncode(setup)}')
      ..addAll(report)
      ..add('  g answered ${jsonEncode(got)}');
  }
  observed['q10'] = seen;
  return lines;
}

/// One case of Q11: `setup` puts (relative to the case's own fresh path `server_rules/q11/<id>`),
/// then one merge at that path with `data` (keys in the order written).
typedef MergeCase = ({
  String id,
  String label,
  List<(String, Object?)> setup,
  Map<String, Object?> data,
});

/// The cases of Q11; two key orders are two cases on two fresh paths (`a` as written, `b`
/// reversed).
List<MergeCase> _q11Cases() {
  final Map<String, Object?> x1 = <String, Object?>{'v': 1, '.priority': 1};
  final Map<String, Object?> xy = <String, Object?>{'y': x1};
  final Map<String, Object?> bx1 = <String, Object?>{'x': x1};
  final Map<String, Object?> bx = <String, Object?>{
    'x': <String, Object?>{'v': 1},
  };
  final List<MergeCase> cases = <MergeCase>[];
  void both(
    String id,
    String label,
    List<(String, Object?)> setup,
    Map<String, Object?> data,
  ) {
    cases
      ..add((
        id: '${id}a',
        label: '$label, as written',
        setup: setup,
        data: data,
      ))
      ..add((
        id: '${id}b',
        label: '$label, reversed',
        setup: setup,
        data: <String, Object?>{
          for (final String k in data.keys.toList().reversed) k: data[k],
        },
      ));
  }

  both(
    'f1',
    'F1 b={x:{y:{v:1,prio 1}}}: m b',
    <(String, Object?)>[
      ('', <String, Object?>{'x': xy}),
    ],
    <String, Object?>{
      'x/y/v': null,
      'x/y/.priority': null,
      'x/.priority': 3,
      '.priority': 2,
    },
  );
  both(
    'f2',
    'F2 x emptied keeping priority 1: m b',
    <(String, Object?)>[('x', x1), ('x/v', null)],
    <String, Object?>{'x/.priority': null, '.priority': 2},
  );
  both(
    'f3',
    'F3 b={x:{v:1,prio 1}}: m b',
    <(String, Object?)>[('', bx1)],
    <String, Object?>{'.priority': 2, 'x/v': null},
  );
  both(
    'f4',
    'F4 b={x:{v:1}} (x no priority): m b',
    <(String, Object?)>[('', bx)],
    <String, Object?>{'.priority': 2, 'x/v': null},
  );
  both(
    'f7',
    'F7 b={x:{v:1,prio 1},k:1}: m b',
    <(String, Object?)>[
      ('', <String, Object?>{'x': x1, 'k': 1}),
    ],
    <String, Object?>{
      '.priority': 2,
      'x/v': null,
      'x/.priority': null,
      'k': null,
    },
  );
  both(
    'f9',
    'F9 b={x:{v:1,w:2,prio 1}}: m b',
    <(String, Object?)>[
      (
        '',
        <String, Object?>{
          'x': <String, Object?>{'v': 1, 'w': 2, '.priority': 1},
        },
      ),
    ],
    <String, Object?>{'.priority': 2, 'x/v': null},
  );
  cases
    ..add((
      id: 'f8a',
      label: 'F8 b={x:{v:1,prio 1}}: m b, x as a nested object with nulls',
      setup: <(String, Object?)>[('', bx1)],
      data: <String, Object?>{
        '.priority': 2,
        'x': <String, Object?>{'v': null, '.priority': null},
      },
    ))
    ..add((
      id: 'f8b',
      label: 'F8 b={x:{v:1,prio 1}}: m b, x as {}',
      setup: <(String, Object?)>[('', bx1)],
      data: <String, Object?>{'.priority': 2, 'x': <String, Object?>{}},
    ));
  return cases;
}

/// Puts [setup] below `server_rules/<group>/<id>`; returns the lines and whether every put
/// answered ok.
Future<List<String>> _q11Setup(
  Kit kit,
  RawConnection raw,
  String id,
  List<(String, Object?)> setup, {
  String group = 'q11',
}) async {
  final List<String> lines = <String>[];
  for (final (String relative, Object? data) in setup) {
    final String path = relative.isEmpty ? id : '$id/$relative';
    final Map<String, Object?> answer = await _answerOrNone(
      kit,
      raw,
      'server_rules/$group',
      (action: 'p', relative: path, data: data),
    );
    lines.add('  setup: ${raw.sent.last}  -> ${jsonEncode(answer)}');
  }
  lines.add(
    '  start export of $id: ${await _export(kit, 'server_rules/$group/$id')}',
  );
  return lines;
}

/// One merge of Q11 on its fresh path: start state, merge report, then `g` of the path.
Future<List<String>> _q11Run(
  Kit kit,
  RawConnection raw,
  Map<String, Object?> seen,
  String id,
  String label,
  List<(String, Object?)> setup,
  Map<String, Object?> data,
) async {
  final List<String> lines = <String>[label];
  lines.addAll(await _q11Setup(kit, raw, id, setup));
  final (List<String> report, Map<String, Object?> one) = await _mergeReport(
    kit,
    raw,
    'q11',
    id,
    id,
    data,
  );
  final Map<String, Object?> got = await raw.get('server_rules/q11/$id');
  one['g'] = jsonEncode(got);
  seen[id] = one;
  return lines
    ..addAll(report)
    ..add('  g answered ${jsonEncode(got)}');
}

/// Q11: merges that empty a child and set a priority, in different shapes and key orders (F1 to
/// F8). F5 sends two merges one after the other, F6 merges one level up.
Future<List<String>> _emptyingMerges(
  Kit kit,
  RawConnection raw,
  Map<String, Object?> observed,
) async {
  final List<String> lines = <String>[
    'q11: start state by raw puts at a fresh path, ONE merge, then g and the REST export',
  ];
  final Map<String, Object?> seen = <String, Object?>{};
  final Map<String, Object?> x1 = <String, Object?>{'v': 1, '.priority': 1};
  for (final MergeCase c in _q11Cases()) {
    lines.addAll(await _q11Run(kit, raw, seen, c.id, c.label, c.setup, c.data));
  }
  // F5: two separate merges at the same node.
  lines.add(
    'F5 b={x:{v:1,prio 1}}: m b {x/v:null, x/.priority:null}, then m b {.priority:2}',
  );
  lines.addAll(
    await _q11Setup(kit, raw, 'f5', <(String, Object?)>[
      ('', <String, Object?>{'x': x1}),
    ]),
  );
  final (List<String> first, Map<String, Object?> one) = await _mergeReport(
    kit,
    raw,
    'q11',
    'f5',
    'f5 merge 1',
    <String, Object?>{'x/v': null, 'x/.priority': null},
  );
  final (List<String> second, Map<String, Object?> two) = await _mergeReport(
    kit,
    raw,
    'q11',
    'f5',
    'f5 merge 2',
    <String, Object?>{'.priority': 2},
  );
  seen['f5'] = <String, Object?>{'first': one, 'second': two};
  lines
    ..addAll(first)
    ..addAll(second);
  // F6: merge one level up, at p, for p/b.
  for (final (String id, Map<String, Object?> data)
      in <(String, Map<String, Object?>)>[
        (
          'f6a',
          <String, Object?>{
            'b/.priority': 2,
            'b/x/v': null,
            'b/x/.priority': null,
          },
        ),
        (
          'f6b',
          <String, Object?>{
            'b/x/.priority': null,
            'b/x/v': null,
            'b/.priority': 2,
          },
        ),
      ]) {
    lines.addAll(
      await _q11Run(
        kit,
        raw,
        seen,
        id,
        'F6 p/b={x:{v:1,prio 1}}: m p, ${id.endsWith('a') ? 'as written' : 'reversed'}',
        <(String, Object?)>[
          ('b', <String, Object?>{'x': x1}),
        ],
        data,
      ),
    );
  }
  observed['q11'] = seen;
  return lines;
}

/// The cases of Q12: a merge whose priority entry lands on a node the same merge creates (A, B,
/// D) or on an emptied node that keeps a priority (C). `_vp` sends the value key first, `_pv` the
/// priority key first.
List<MergeCase> _q12Cases() {
  final List<(String, Object?)> sibling = <(String, Object?)>[
    ('', <String, Object?>{'k': 1}),
  ];
  final List<(String, Object?)> emptied = <(String, Object?)>[
    ('x', <String, Object?>{'v': 1, '.priority': 5}),
    ('x/v', null),
  ];
  final List<MergeCase> cases = <MergeCase>[];
  void both(
    String id,
    String label,
    List<(String, Object?)> setup,
    String value,
    String priority,
  ) {
    cases
      ..add((
        id: '${id}_vp',
        label: '$label, value key first',
        setup: setup,
        data: <String, Object?>{value: 1, priority: 3},
      ))
      ..add((
        id: '${id}_pv',
        label: '$label, priority key first',
        setup: setup,
        data: <String, Object?>{priority: 3, value: 1},
      ));
  }

  both('a', 'A r={k:1}, x missing: m r', sibling, 'x/v', 'x/.priority');
  both(
    'a0',
    'A0 r missing (so x missing): m r',
    const <(String, Object?)>[],
    'x/v',
    'x/.priority',
  );
  for (final (String id, String label, List<(String, Object?)> setup)
      in <(String, String, List<(String, Object?)>)>[
        ('b', 'B control r={k:1}: m r, x as an object', sibling),
        ('b0', 'B0 control r missing: m r, x as an object', const []),
      ]) {
    cases.add((
      id: id,
      label: label,
      setup: setup,
      data: <String, Object?>{
        'x': <String, Object?>{'v': 1, '.priority': 3},
      },
    ));
  }
  both(
    'c',
    'C x emptied keeping priority 5: m r',
    emptied,
    'x/v',
    'x/.priority',
  );
  cases.add((
    id: 'c_p',
    label: 'C x emptied keeping priority 5: m r, priority alone',
    setup: emptied,
    data: <String, Object?>{'x/.priority': 3},
  ));
  both('d', 'D r missing: m r', const <(String, Object?)>[], 'v', '.priority');
  return cases;
}

/// One case of Q12 at `server_rules/q12/<id>`: the setup puts, the start export and `g`, the
/// merge report, then `g` again. A `g` without an answer is printed as `NO ANSWER`.
Future<List<String>> _q12Run(
  Kit kit,
  RawConnection raw,
  Map<String, Object?> seen,
  MergeCase c,
) async {
  final List<String> lines = <String>[c.label];
  lines.addAll(await _q11Setup(kit, raw, c.id, c.setup, group: 'q12'));
  const String node = 'server_rules/q12';
  final RuleOp read = (action: 'g', relative: c.id, data: null);
  final Map<String, Object?> start = await _answerOrNone(kit, raw, node, read);
  lines.add('  start g answered ${jsonEncode(start)}');
  final (List<String> report, Map<String, Object?> one) = await _mergeReport(
    kit,
    raw,
    'q12',
    c.id,
    c.id,
    c.data,
  );
  final Map<String, Object?> got = await _answerOrNone(kit, raw, node, read);
  one['start'] = jsonEncode(start);
  one['g'] = jsonEncode(got);
  seen[c.id] = one;
  return lines
    ..addAll(report)
    ..add('  g answered ${jsonEncode(got)}');
}

/// Q12: does a priority entry land on a node that the same merge creates, and is the refusal
/// "could not set priority on non-existent node" decided before or after the values are written?
/// Printed as observations; the check passes whatever the server answers.
Future<List<String>> _priorityOnCreatedNode(
  Kit kit,
  RawConnection raw,
  Map<String, Object?> observed,
) async {
  final List<String> lines = <String>[
    'q12: start state by raw puts at a fresh path r = server_rules/q12/<id>, ONE merge at r, '
        'then g and the REST export',
  ];
  final Map<String, Object?> seen = <String, Object?>{};
  for (final MergeCase c in _q12Cases()) {
    lines.addAll(await _q12Run(kit, raw, seen, c));
  }
  lines.add('q12 observations (answer, then g after the merge):');
  for (final MapEntry<String, Object?> e in seen.entries) {
    final Map<String, Object?> one = e.value! as Map<String, Object?>;
    lines.add('  observation ${e.key}: ${one['answer']}  g ${one['g']}');
  }
  observed['q12'] = seen;
  return lines;
}

/// One case of Q13: start puts at `server_rules/q13/<id>`, then one onDisconnect merge (`om`) at it.
typedef DisconnectCase = ({
  String id,
  String label,
  List<(String, Object?)> setup,
  Map<String, Object?> data,
});

/// The cases of Q13: r = {k:1}, x missing; `_vp` sends the value key first, `_pv` the priority
/// key first, `b` is the object form.
List<DisconnectCase> _q13Cases() {
  final List<(String, Object?)> sibling = <(String, Object?)>[
    ('', <String, Object?>{'k': 1}),
  ];
  return <DisconnectCase>[
    (
      id: 'a_vp',
      label: 'Q13 A r={k:1}, x missing: om r, value key first',
      setup: sibling,
      data: <String, Object?>{'x/v': 1, 'x/.priority': 3},
    ),
    (
      id: 'a_pv',
      label: 'Q13 A r={k:1}, x missing: om r, priority key first',
      setup: sibling,
      data: <String, Object?>{'x/.priority': 3, 'x/v': 1},
    ),
    (
      id: 'b',
      label: 'Q13 B control r={k:1}: om r, x as an object',
      setup: sibling,
      data: <String, Object?>{
        'x': <String, Object?>{'v': 1, '.priority': 3},
      },
    ),
  ];
}

/// One case of Q13 on a connection of its own: the setup puts, the `om`, its answer and frames,
/// then the socket dropped without a WebSocket close, 5 s, and the REST export of the path.
Future<List<String>> _q13Run(
  Kit kit,
  Map<String, Object?> seen,
  DisconnectCase c,
) async {
  final RawConnection own = await RawConnection.open(kit);
  final List<String> lines = <String>[c.label];
  lines.addAll(await _q11Setup(kit, own, c.id, c.setup, group: 'q13'));
  final int mark = own.frames.length;
  final int sentAt = own.elapsedMs;
  Map<String, Object?> answer;
  try {
    answer = await own.request('om', <String, Object?>{
      'p': '/${kit.runPath}/server_rules/q13/${c.id}',
      'd': c.data,
    });
  } on KitTimeout {
    answer = <String, Object?>{
      's': 'NO ANSWER',
      'd': 'none within ${stepWait.inSeconds} s',
    };
  }
  final List<String> frames = <String>[
    for (final f in own.frames.skip(mark)) '+${f.ms - sentAt} ms ${f.text}',
  ];
  own.destroy();
  await Future<void>.delayed(const Duration(seconds: 5));
  final String export = await _export(kit, 'server_rules/q13/${c.id}');
  seen[c.id] = <String, Object?>{
    'answer': jsonEncode(answer),
    'frames': frames,
    'export': export,
  };
  return lines..addAll(<String>[
    '  sent: ${own.sent.last}',
    '  answer: ${jsonEncode(answer)}',
    for (final String frame in frames) '  frame: $frame',
    if (frames.isEmpty) '  frame: NO FRAME',
    '  socket dropped without a close; export of ${c.id} 5 s later: $export',
  ]);
}

/// Q13: the onDisconnect merge (`om`) with a priority entry on a node it creates, each case on a
/// fresh path and a connection of its own. Printed as observations.
Future<List<String>> _disconnectPriority(
  Kit kit,
  Map<String, Object?> observed,
) async {
  final List<String> lines = <String>[
    'q13: r = server_rules/q13/<id> = {k:1} by a raw put, ONE om at r, the socket dropped '
        'without a close, then the REST export of r after 5 s',
  ];
  final Map<String, Object?> seen = <String, Object?>{};
  for (final DisconnectCase c in _q13Cases()) {
    lines.addAll(await _q13Run(kit, seen, c));
  }
  lines.add(
    'q13 observations (answer to om, then the export 5 s after the drop):',
  );
  for (final MapEntry<String, Object?> e in seen.entries) {
    final Map<String, Object?> one = e.value! as Map<String, Object?>;
    lines.add(
      '  observation ${e.key}: ${one['answer']}  export ${one['export']}',
    );
  }
  observed['q13'] = seen;
  return lines;
}

/// Q14: a merge that removes the priority of `x` (`{"x/.priority": null}`), with x missing and
/// with x holding a value and a priority. Printed as observations.
Future<List<String>> _priorityRemoval(
  Kit kit,
  RawConnection raw,
  Map<String, Object?> observed,
) async {
  final List<String> lines = <String>[
    'q14: start state by raw puts at a fresh path r = server_rules/q14/<id>, ONE merge at r, '
        'then g and the REST export',
  ];
  final Map<String, Object?> seen = <String, Object?>{};
  const String node = 'server_rules/q14';
  for (final (String id, String label, Map<String, Object?> start)
      in <(String, String, Map<String, Object?>)>[
        ('missing', 'Q14 r={k:1}, x missing', <String, Object?>{'k': 1}),
        (
          'existing',
          'Q14 r={k:1, x:{v:1, prio 2}}',
          <String, Object?>{
            'k': 1,
            'x': <String, Object?>{'v': 1, '.priority': 2},
          },
        ),
      ]) {
    lines
      ..add('$label: m r {"x/.priority":null}')
      ..addAll(
        await _q11Setup(kit, raw, id, <(String, Object?)>[
          ('', start),
        ], group: 'q14'),
      );
    final (List<String> report, Map<String, Object?> one) = await _mergeReport(
      kit,
      raw,
      'q14',
      id,
      id,
      <String, Object?>{'x/.priority': null},
    );
    final Map<String, Object?> got = await _answerOrNone(kit, raw, node, (
      action: 'g',
      relative: id,
      data: null,
    ));
    one['g'] = jsonEncode(got);
    seen[id] = one;
    lines
      ..addAll(report)
      ..add('  g answered ${jsonEncode(got)}');
  }
  lines.add('q14 observations (answer, then the export after the merge):');
  for (final MapEntry<String, Object?> e in seen.entries) {
    final Map<String, Object?> one = e.value! as Map<String, Object?>;
    lines.add(
      '  observation ${e.key}: ${one['answer']}  export ${one['export']}',
    );
  }
  observed['q14'] = seen;
  return lines;
}

Future<CheckResult> _serverRules(Kit kit) async {
  final RawConnection raw = await RawConnection.open(kit);
  final Map<String, Object?> observed = <String, Object?>{};
  final List<String> details = <String>[];
  for (final RuleCase c in ruleCases()) {
    details.addAll(await _runRuleCase(kit, raw, c, observed));
  }
  details.addAll(await _compoundRanges(kit, raw, observed));
  details.addAll(await _priorityOnlyChild(kit, raw, observed));
  details.addAll(await _priorityOnlyForms(kit, raw, observed));
  details.addAll(await _mergeKeyOrder(kit, raw, observed));
  details.addAll(await _emptyingMerges(kit, raw, observed));
  details.addAll(await _priorityOnCreatedNode(kit, raw, observed));
  details.addAll(await _priorityRemoval(kit, raw, observed));
  details.addAll(await _disconnectPriority(kit, observed));
  String field(String id, String key) =>
      '${(observed[id]! as Map<String, Object?>)[key]}';
  final String exports = <String>[
    for (final RuleCase c in ruleCases()) '${c.id} ${field(c.id, 'export')}',
  ].join(', ');
  return CheckResult(
    Status.pass,
    'Raw frames only; the export after each case (before its transaction put): $exports; q5 '
    '(compound hash): without the kept priorities ${field('q5_without', 'kind')}, with them '
    '${field('q5_withPriority', 'kind')} (as a leaf) and ${field('q5_withEmpty', 'kind')} '
    '(as an empty range).',
    details: details,
    observed: observed,
  );
}

// -----------------------------------------------------------------------------------------------
// Check 40: a plain set of a null priority on a node that does not exist.

/// One public API write of check 40 at its own fresh path `null_priority/api/<id>`.
typedef NullPriorityForm = ({
  String id,
  String label,
  Future<void> Function(DatabaseReference ref) write,
});

/// The writes of check 40 that the client's validation lets through: (a) `setPriority(null)` and
/// every `set` form that holds no value, then (c) `setPriority(3)` for comparison. The client
/// parses each `set` form here into an empty node and sends it as `p <path> null`; only
/// `setPriority` sends `p <path>/.priority <priority>`.
List<NullPriorityForm> _nullPriorityForms() => <NullPriorityForm>[
  (
    id: 'sp_null',
    label: '(a) setPriority(null)',
    write: (DatabaseReference r) => r.setPriority(null),
  ),
  (
    id: 'set_null_p3',
    label: '(a) set(null, priority: 3)',
    write: (DatabaseReference r) => r.set(null, priority: 3),
  ),
  (
    id: 'set_map_p3',
    label: '(a) set({}, priority: 3)',
    write: (DatabaseReference r) => r.set(<String, Object?>{}, priority: 3),
  ),
  (
    id: 'set_list_p3',
    label: '(a) set([], priority: 3)',
    write: (DatabaseReference r) => r.set(<Object?>[], priority: 3),
  ),
  (
    id: 'set_dot_p3',
    label: "(a) set({'.priority': 3})",
    write: (DatabaseReference r) => r.set(<String, Object?>{'.priority': 3}),
  ),
  (
    id: 'set_value_null_p3',
    label: "(a) set({'.value': null, '.priority': 3})",
    write: (DatabaseReference r) =>
        r.set(<String, Object?>{'.value': null, '.priority': 3}),
  ),
  (
    id: 'set_value_map_p3',
    label: "(a) set({'.value': {}, '.priority': 3})",
    write: (DatabaseReference r) =>
        r.set(<String, Object?>{'.value': <String, Object?>{}, '.priority': 3}),
  ),
  (
    id: 'set_dot_null',
    label: "(a) set({'.priority': null})",
    write: (DatabaseReference r) => r.set(<String, Object?>{'.priority': null}),
  ),
  (
    id: 'sp_3',
    label: '(c) setPriority(3)',
    write: (DatabaseReference r) => r.setPriority(3),
  ),
];

/// Value-less calls of check 40 that the client refuses at the call, before anything is sent.
List<(String, Future<void> Function(DatabaseReference ref))>
_refusedNullPriorityForms() =>
    <(String, Future<void> Function(DatabaseReference ref))>[
      (
        "child('.priority').set(null)",
        (DatabaseReference r) => r.child('.priority').set(null),
      ),
      (
        'set(null, priority: true)',
        (DatabaseReference r) => r.set(null, priority: true),
      ),
      (
        "set({'.priority': true})",
        (DatabaseReference r) => r.set(<String, Object?>{'.priority': true}),
      ),
      (
        "set({'.priority': {}})",
        (DatabaseReference r) =>
            r.set(<String, Object?>{'.priority': <String, Object?>{}}),
      ),
      (
        "set({'.value': null, '.priority': 3, 'a': null})",
        (DatabaseReference r) =>
            r.set(<String, Object?>{'.value': null, '.priority': 3, 'a': null}),
      ),
    ];

/// A snapshot as `<value> priority <priority>`.
String _snapText(DataSnapshot s) =>
    '${_clip(s.value)} priority ${jsonEncode(s.priority)}';

/// A refusal in full: code, server status and message.
String _refusalText(FirebaseDatabaseException e) =>
    'code ${e.code}, serverStatus "${e.serverStatus}", message "${e.message}"';

/// What `get()` of [ref] gives: the snapshot, the refusal, or `NOT COMPLETED` after the step wait.
Future<String> _getText(DatabaseReference ref, String what) async {
  try {
    return _snapText(await within(ref.get(), what));
  } on FirebaseDatabaseException catch (e) {
    return 'failed: ${_refusalText(e)}';
  } on KitTimeout {
    return 'NOT COMPLETED within ${stepWait.inSeconds} s';
  }
}

/// One write of check 40 (a) or (c) at `null_priority/api/<id>`, which does not exist: a value
/// listener of the writer attached first, the write (how its Future ended, or `NOT COMPLETED`
/// after the step wait), the listener's events, the writer's get() with the listener still
/// attached, a fresh client's get() and the REST export.
Future<List<String>> _nullPriorityApiRun(
  Kit kit,
  KitDb writer,
  KitDb fresh,
  NullPriorityForm form,
  Map<String, Object?> seen,
) async {
  final String relative = 'null_priority/api/${form.id}';
  final DatabaseReference ref = writer.ref(relative);
  final Recorder<DatabaseEvent> events = Recorder<DatabaseEvent>(ref.onValue);
  await until(
    () => events.items.isNotEmpty || events.error != null,
    'the first event at $relative',
  );
  final int before = events.items.length;
  final Stopwatch watch = Stopwatch()..start();
  String result;
  final Future<void> write = form.write(ref);
  handled(write);
  try {
    await within(write, form.label);
    result = 'completed ok after ${watch.elapsedMilliseconds} ms';
  } on FirebaseDatabaseException catch (e) {
    result = 'failed after ${watch.elapsedMilliseconds} ms: ${_refusalText(e)}';
  } on KitTimeout {
    kit.lateWritesPossible = true;
    result =
        'NOT COMPLETED within ${stepWait.inSeconds} s (the kit stopped waiting)';
  }
  await Future<void>.delayed(_listenSettle);
  final List<String> first = <String>[
    for (final DatabaseEvent e in events.items.take(before))
      _snapText(e.snapshot),
  ];
  final List<String> after = <String>[
    for (final DatabaseEvent e in events.items.skip(before))
      _snapText(e.snapshot),
  ];
  final Object? listenerError = events.error;
  final String own = await _getText(ref, 'get() of $relative by the writer');
  await events.cancel();
  final String other = await _getText(
    fresh.ref(relative),
    'get() of $relative by a fresh client',
  );
  final String export = await _export(kit, relative);
  seen[form.id] = <String, Object?>{
    'write': result.replaceFirst(RegExp(r' after \d+ ms'), ''),
    'listenerBefore': first,
    'listenerAfter': after,
    'listenerError': listenerError == null ? null : describe(listenerError),
    'get': own,
    'freshGet': other,
    'export': export,
  };
  return <String>[
    '${form.label} at $relative (missing)',
    '  write: $result',
    '  listener attached before: ${first.join(' | ')}; after the write: '
        '${after.isEmpty ? 'NO EVENT' : after.join(' | ')}'
        '${listenerError == null ? '' : '; listener error ${describe(listenerError)}'}',
    '  get() by the writer (listener still attached): $own',
    '  get() by a fresh client: $other',
    '  export: $export',
  ];
}

/// Check 40 (a): the value-less calls the client refuses at the call; each error's first line.
Future<List<String>> _nullPriorityRefusedAtCall(
  KitDb writer,
  Map<String, Object?> seen,
) async {
  final List<String> lines = <String>[
    '(a) refused at the call, nothing sent (each at null_priority/refused/<n>):',
  ];
  int n = 0;
  for (final (String label, Future<void> Function(DatabaseReference) call)
      in _refusedNullPriorityForms()) {
    final DatabaseReference ref = writer.ref('null_priority/refused/${n++}');
    String result;
    try {
      final Future<void> write = call(ref);
      handled(write);
      result =
          'NOT REFUSED AT THE CALL: ${outcome(await refusal(write, label))}';
    } on ArgumentError catch (e) {
      result = 'ArgumentError: ${'$e'.split('\n').first}';
    }
    seen[label] = result;
    lines.add('  $label: $result');
  }
  return lines;
}

/// One raw case of check 40 (b) at `null_priority/raw/<id>` (r): the setup puts relative to r, then
/// one put of `data` at `r/<target>`.
typedef NullPriorityFrame = ({
  String id,
  String label,
  List<(String, Object?)> setup,
  String target,
  Object? data,
});

/// The raw cases of check 40 (b): b1 and b2 the question, b3 to b5 controls on an existing x,
/// b6 the non-null priority on a missing x for comparison.
List<NullPriorityFrame> _nullPriorityFrames() {
  const Map<String, Object?> k = <String, Object?>{'k': 1};
  return <NullPriorityFrame>[
    (
      id: 'b1',
      label: '(b1) r missing (so x missing): p r/x/.priority null',
      setup: const <(String, Object?)>[],
      target: 'x/.priority',
      data: null,
    ),
    (
      id: 'b2',
      label: '(b2) r={k:1}, x missing: p r/x/.priority null',
      setup: const <(String, Object?)>[('', k)],
      target: 'x/.priority',
      data: null,
    ),
    (
      id: 'b3',
      label:
          '(b3) control r={k:1, x:{v:1}} (x no priority): p r/x/.priority null',
      setup: const <(String, Object?)>[
        (
          '',
          <String, Object?>{
            'k': 1,
            'x': <String, Object?>{'v': 1},
          },
        ),
      ],
      target: 'x/.priority',
      data: null,
    ),
    (
      id: 'b4',
      label: '(b4) control r={k:1, x:{v:1} priority 2}: p r/x/.priority null',
      setup: const <(String, Object?)>[
        (
          '',
          <String, Object?>{
            'k': 1,
            'x': <String, Object?>{'v': 1, '.priority': 2},
          },
        ),
      ],
      target: 'x/.priority',
      data: null,
    ),
    (
      id: 'b5',
      label:
          '(b5) control r={k:1}, x emptied keeping priority 5: p r/x/.priority null',
      setup: const <(String, Object?)>[
        (
          '',
          <String, Object?>{
            'k': 1,
            'x': <String, Object?>{'v': 1, '.priority': 5},
          },
        ),
        ('x/v', null),
      ],
      target: 'x/.priority',
      data: null,
    ),
    (
      id: 'b6',
      label: '(b6) comparison r={k:1}, x missing: p r/x/.priority 3',
      setup: const <(String, Object?)>[('', k)],
      target: 'x/.priority',
      data: 3,
    ),
  ];
}

/// One raw case of check 40 (b): the setup puts and the start export, a listen at r, the put
/// (sent frame verbatim, the answer or `NO ANSWER` after the step wait, every frame received
/// within 1 s after it with `+N ms`), the unlisten, a `g` of r and the REST export of r.
Future<List<String>> _nullPriorityFrameRun(
  Kit kit,
  RawConnection raw,
  NullPriorityFrame c,
  Map<String, Object?> seen,
) async {
  const String group = 'null_priority/raw';
  final String r = '$group/${c.id}';
  final List<String> lines = <String>[c.label];
  for (final (String relative, Object? data) in c.setup) {
    final Map<String, Object?> answer = await _answerOrNone(kit, raw, group, (
      action: 'p',
      relative: relative.isEmpty ? c.id : '${c.id}/$relative',
      data: data,
    ));
    lines.add('  setup: ${raw.sent.last}  -> ${jsonEncode(answer)}');
  }
  lines.add('  start export of r: ${await _export(kit, r)}');
  final Map<String, Object?> listen = await raw.listenAnswer(r);
  await Future<void>.delayed(_listenSettle);
  final int mark = raw.frames.length;
  final int sentMark = raw.sent.length;
  final int sentAt = raw.elapsedMs;
  final Map<String, Object?> answer = await _answerOrNone(kit, raw, group, (
    action: 'p',
    relative: '${c.id}/${c.target}',
    data: c.data,
  ));
  await Future<void>.delayed(const Duration(seconds: 1));
  final List<String> frames = <String>[
    for (final f in raw.frames.skip(mark)) '+${f.ms - sentAt} ms ${f.text}',
  ];
  final String sent = raw.sent.skip(sentMark).join(' | ');
  String unlisten = 'ok';
  try {
    await raw.unlisten(r, _noQuery, null);
  } on KitTimeout {
    unlisten = 'NO ANSWER within ${stepWait.inSeconds} s';
  }
  final Map<String, Object?> got = await _answerOrNone(kit, raw, group, (
    action: 'g',
    relative: c.id,
    data: null,
  ));
  final String export = await _export(kit, r);
  seen[c.id] = <String, Object?>{
    'sent': sent.replaceAll('/${kit.runPath}/', '/<run>/'),
    'answer': jsonEncode(answer),
    'g': jsonEncode(got),
    'export': export,
  };
  return lines..addAll(<String>[
    '  listen r answered ${jsonEncode(listen)}',
    '  sent: $sent',
    '  answer: ${jsonEncode(answer)}',
    for (final String frame in frames) '  frame: $frame',
    if (frames.isEmpty) '  frame: NO FRAME',
    '  unlisten: $unlisten',
    '  g of r answered ${jsonEncode(got)}',
    '  export of r: $export',
  ]);
}

/// The `write` field of the form [id] in [seen], or `?` when it did not run.
String _apiWrite(Map<String, Object?> seen, String id) =>
    '${(seen[id] as Map<String, Object?>?)?['write'] ?? '?'}';

/// Check 40: a plain set of a null priority on a node that does not exist. (a) and (c) through the
/// public API, (b) as raw frames. Printed as observations; the check passes whatever the server
/// answers.
Future<CheckResult> _nullPriorityOnMissing(Kit kit) async {
  final KitDb writer = kit.open();
  final KitDb fresh = kit.open();
  final RawConnection raw = await RawConnection.open(kit);
  final Map<String, Object?> api = <String, Object?>{};
  final Map<String, Object?> refused = <String, Object?>{};
  final Map<String, Object?> frames = <String, Object?>{};
  final List<String> details = <String>[];
  for (final NullPriorityForm form in _nullPriorityForms()) {
    details.addAll(await _nullPriorityApiRun(kit, writer, fresh, form, api));
  }
  details.addAll(await _nullPriorityRefusedAtCall(writer, refused));
  for (final NullPriorityFrame c in _nullPriorityFrames()) {
    details.addAll(await _nullPriorityFrameRun(kit, raw, c, frames));
  }
  final Map<String, Object?> after = await _answerOrNone(
    kit,
    raw,
    'null_priority/raw',
    _put('after', 1),
  );
  details.add(
    '(b) after: put null_priority/raw/after 1 on the same connection: ${jsonEncode(after)}',
  );
  frames['after'] = jsonEncode(after);
  final Set<String> setForms = <String>{
    for (final NullPriorityForm f in _nullPriorityForms())
      if (f.id.startsWith('set_')) _apiWrite(api, f.id),
  };
  String rawAnswer(String id) =>
      '${(frames[id]! as Map<String, Object?>)['answer']}';
  return CheckResult(
    Status.pass,
    'A null priority on a missing node. (a) setPriority(null): ${_apiWrite(api, 'sp_null')}; '
    'the value-less set forms (each sent as p <path> null): ${setForms.join(' / ')}. '
    '(b) raw p x/.priority null, r and x missing: ${rawAnswer('b1')}; '
    'r={k:1}, x missing: ${rawAnswer('b2')}; x {v:1}: ${rawAnswer('b3')}; x priority 2: '
    '${rawAnswer('b4')}; x emptied priority 5: ${rawAnswer('b5')}; p x/.priority 3, x missing: '
    '${rawAnswer('b6')}. (c) setPriority(3): ${_apiWrite(api, 'sp_3')}. Details below.',
    details: details,
    observed: <String, Object?>{'api': api, 'refused': refused, 'raw': frames},
  );
}

// -----------------------------------------------------------------------------------------------
// Check 41: a merge key that names the merge's own location.

/// One raw case of check 41: the merge `data` sent at `<run>/empty_merge_key/<id>/loc`.
typedef EmptyMergeKeyCase = ({
  String id,
  String label,
  Map<String, Object?> data,
});

/// The cases of check 41: each key that parses to the empty path (`''`, `'/'`, `'//'`) alone and
/// beside a normal key.
List<EmptyMergeKeyCase> _emptyMergeKeyCases() => <EmptyMergeKeyCase>[
  for (final (int i, String key) in <(int, String)>[
    (1, ''),
    (2, '/'),
    (3, '//'),
  ]) ...<EmptyMergeKeyCase>[
    (
      id: 'a$i',
      label: '(a$i) m loc ${jsonEncode(<String, Object?>{key: 7})}',
      data: <String, Object?>{key: 7},
    ),
    (
      id: 'a${i + 3}',
      label:
          '(a${i + 3}) m loc ${jsonEncode(<String, Object?>{key: 7, 'n': 3})}',
      data: <String, Object?>{key: 7, 'n': 3},
    ),
  ],
];

/// The frames [connection] received since [mark], each with `+N ms` after [sentAt], or
/// `NO FRAME`.
List<String> _framesSince(RawConnection connection, int mark, int sentAt) {
  final List<String> frames = <String>[
    for (final f in connection.frames.skip(mark))
      '+${f.ms - sentAt} ms ${f.text}',
  ];
  return frames.isEmpty ? <String>['NO FRAME'] : frames;
}

/// One case of check 41 at `<run>/empty_merge_key/<id>` (up): the writer of [raw] puts up =
/// `{loc: {k: 1, j: 2}, sib: 5}`, its `atLoc` listens at `up/loc` and its `above` at up, then
/// the writer sends the merge at `up/loc`. Prints the frame sent, the answer (or `NO ANSWER` after
/// the step wait), every frame each connection received within 1 s, a `g` of up and the REST export
/// of up.
Future<List<String>> _emptyMergeKeyRun(
  Kit kit,
  ({RawConnection writer, RawConnection atLoc, RawConnection above}) raw,
  EmptyMergeKeyCase c,
  Map<String, Object?> seen,
) async {
  const String group = 'empty_merge_key';
  final String up = '$group/${c.id}';
  final List<String> lines = <String>[c.label];
  final Map<String, Object?> setup = await _answerOrNone(
    kit,
    raw.writer,
    group,
    _put(c.id, <String, Object?>{
      'loc': <String, Object?>{'k': 1, 'j': 2},
      'sib': 5,
    }),
  );
  final String startExport = await _export(kit, up);
  lines
    ..add('  setup: ${raw.writer.sent.last}  -> ${jsonEncode(setup)}')
    ..add('  start export of up: $startExport');
  final Map<String, Object?> listenLoc = await raw.atLoc.listenAnswer(
    '$up/loc',
  );
  final Map<String, Object?> listenUp = await raw.above.listenAnswer(up);
  await Future<void>.delayed(_listenSettle);
  final int locMark = raw.atLoc.frames.length;
  final int upMark = raw.above.frames.length;
  final int writerMark = raw.writer.frames.length;
  final int sentMark = raw.writer.sent.length;
  final int sentAt = raw.writer.elapsedMs;
  final Map<String, Object?> answer = await _answerOrNone(
    kit,
    raw.writer,
    group,
    (action: 'm', relative: '${c.id}/loc', data: c.data),
  );
  await Future<void>.delayed(const Duration(seconds: 1));
  final String sent = raw.writer.sent.skip(sentMark).join(' | ');
  final List<String> atLoc = _framesSince(raw.atLoc, locMark, sentAt);
  final List<String> above = _framesSince(raw.above, upMark, sentAt);
  final List<String> writer = _framesSince(raw.writer, writerMark, sentAt);
  final List<String> unlistened = <String>[];
  for (final (RawConnection connection, String relative)
      in <(RawConnection, String)>[(raw.atLoc, '$up/loc'), (raw.above, up)]) {
    try {
      await connection.unlisten(relative, _noQuery, null);
      unlistened.add('ok');
    } on KitTimeout {
      unlistened.add('NO ANSWER within ${stepWait.inSeconds} s');
    }
  }
  final Map<String, Object?> got = await _answerOrNone(kit, raw.writer, group, (
    action: 'g',
    relative: c.id,
    data: null,
  ));
  final String export = await _export(kit, up);
  seen[c.id] = <String, Object?>{
    'setup': jsonEncode(setup),
    'startExport': startExport,
    'listen': <String>[jsonEncode(listenLoc), jsonEncode(listenUp)],
    'sent': sent.replaceAll('/${kit.runPath}/', '/<run>/'),
    'answer': jsonEncode(answer),
    // The writer's frames within 1 s of the merge, without their timing.
    'writerFrames': <String>[
      for (final String frame in writer)
        frame.replaceFirst(RegExp(r'^\+-?\d+ ms '), ''),
    ],
    'unlisten': unlistened,
    'pushedAtLoc': atLoc.first == 'NO FRAME' ? 0 : atLoc.length,
    'pushedAbove': above.first == 'NO FRAME' ? 0 : above.length,
    'g': jsonEncode(got),
    'export': export,
  };
  return lines..addAll(<String>[
    '  listen up/loc answered ${jsonEncode(listenLoc)}; listen up answered ${jsonEncode(listenUp)}',
    '  sent: $sent',
    '  answer: ${jsonEncode(answer)}',
    for (final String frame in writer) '  writer frame: $frame',
    for (final String frame in atLoc) '  listener at up/loc frame: $frame',
    for (final String frame in above) '  listener at up frame: $frame',
    '  unlisten: ${unlistened.join(', ')}',
    '  g of up answered ${jsonEncode(got)}',
    '  export of up: $export',
  ]);
}

/// Check 41: a merge (`m`) whose key parses to the empty path (`''`, `'/'`, `'//'`), alone and
/// beside a normal key, as raw frames on three connections (writer, a listener at the merge's
/// location, a listener above it). Printed as observations; the check passes whatever the server
/// answers.
Future<CheckResult> _emptyMergeKey(Kit kit) async {
  final ({RawConnection writer, RawConnection atLoc, RawConnection above}) raw =
      (
        writer: await RawConnection.open(kit),
        atLoc: await RawConnection.open(kit),
        above: await RawConnection.open(kit),
      );
  final Map<String, Object?> seen = <String, Object?>{};
  final List<String> details = <String>[];
  for (final EmptyMergeKeyCase c in _emptyMergeKeyCases()) {
    details.addAll(await _emptyMergeKeyRun(kit, raw, c, seen));
  }
  final Map<String, Object?> after = await _answerOrNone(
    kit,
    raw.writer,
    'empty_merge_key',
    _put('after', 1),
  );
  details.add(
    'after: put empty_merge_key/after 1 on the writer connection: ${jsonEncode(after)}',
  );
  seen['after'] = jsonEncode(after);
  String line(String id) {
    final Map<String, Object?> s = seen[id]! as Map<String, Object?>;
    return '${s['answer']}, pushes ${s['pushedAtLoc']}/${s['pushedAbove']}, export ${s['export']}';
  }

  return CheckResult(
    Status.pass,
    'A merge key that names the location itself, up = {loc:{k:1,j:2}, sib:5}, m at up/loc '
    '(answer, pushes to the listeners at up/loc and up, export of up): '
    '{"":7}: ${line('a1')}; {"/":7}: ${line('a2')}; {"//":7}: ${line('a3')}; '
    '{"":7,"n":3}: ${line('a4')}; {"/":7,"n":3}: ${line('a5')}; {"//":7,"n":3}: ${line('a6')}. '
    'Details below.',
    details: details,
    observed: <String, Object?>{'raw': seen},
  );
}

/// Checks 27 to 41, appended to the kit's list.
const List<Check> questionChecks = <Check>[
  Check(
    '27',
    'Questions 1-3: priorities',
    Scope.production,
    _priorityQuestions,
  ),
  Check(
    '28',
    'Questions 4-10: frames to a limit query',
    Scope.production,
    _limitFrames,
  ),
  Check(
    '29',
    'Question 11: tagged frame before untagged',
    Scope.production,
    _taggedFirst,
  ),
  Check(
    '30',
    'Questions 12-14: writes below a leaf',
    Scope.production,
    _belowLeaf,
  ),
  Check(
    '31',
    'Questions 15-19: transactions',
    Scope.production,
    _transactionQuestions,
  ),
  Check(
    '32',
    'Question 23: a 1 MB child and a small listener',
    Scope.production,
    _largeChild,
  ),
  Check(
    '33',
    'Question 24: onDisconnect after a dropped socket',
    Scope.production,
    _droppedSocket,
  ),
  Check(
    '34',
    'Question 26: pipelined increments, two clients',
    Scope.production,
    _pipelinedIncrements,
  ),
  Check(
    '35',
    'Question 28: server limits (depth 33)',
    Scope.production,
    _serverLimits,
  ),
  Check(
    '36',
    'Question 29: 1,000 pipelined updates',
    Scope.production,
    _pipelinedUpdates,
  ),
  Check(
    '37',
    'Priority window: a child moved into and out of a limit',
    Scope.production,
    _priorityWindow,
  ),
  Check(
    '38',
    'Priority of an emptied node: frames, update, hash, deletion',
    Scope.production,
    _emptiedPriority,
  ),
  Check(
    '39',
    'Server rules for an emptied node\'s priority, raw frames',
    Scope.production,
    _serverRules,
    wait: Duration(minutes: 8),
  ),
  Check(
    '40',
    'A null priority set on a missing node',
    Scope.production,
    _nullPriorityOnMissing,
    wait: Duration(minutes: 8),
  ),
  Check(
    '41',
    'A merge key that names the location itself, raw frames',
    Scope.production,
    _emptyMergeKey,
    wait: Duration(minutes: 8),
  ),
];
