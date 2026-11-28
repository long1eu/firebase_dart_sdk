// The Error Reporting probe. It answers the questions of
// docs/error_reporting_spec.md, section 11, before the client's message format
// is fixed: Cloud Error Reporting parses no Dart stack traces, so how does it
// take Dart frames rewritten into the V8 format, or a raw Dart trace with a
// reportLocation? See tool/error_reporting_probe.md.
//
// It sends a set of error events, each labelled with a case id and a run tag,
// to projects.events.report of one Google Cloud project, prints the HTTP
// status of each, and then prints what to look for in the Error Reporting
// console. It sends nothing without --yes. The credential comes from the
// environment and is never printed: server text is redacted before it is
// shown.
//
// From the repository root, with an access token:
//
//   export ER_PROJECT_ID=my-project
//   export ER_ACCESS_TOKEN="$(gcloud auth print-access-token)"
//   dart tool/error_reporting_probe.dart          # prints the plan, sends nothing
//   dart tool/error_reporting_probe.dart --yes    # sends
//
// or with an API key restricted to the Error Reporting API:
//
//   read -rs ER_API_KEY && export ER_API_KEY
//
// Only dart:io and dart:convert, so it runs with a plain `dart` and no pub get.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const String _usage = '''
Usage: dart tool/error_reporting_probe.dart [--yes] [--print] [--only=ID,...]

Environment:
  ER_PROJECT_ID      the Google Cloud project id (the projectId of the Firebase app)
  ER_ACCESS_TOKEN    an OAuth access token with the Error Reporting Writer role, or
  ER_API_KEY         an API key restricted to the Error Reporting API
  ER_OTHER_API_KEY   optional: a key restricted to another API, for case K1

Without --yes it prints the plan and sends nothing.
--print prints the request bodies and exits; it needs no credential.
--only sends the listed cases only (for example --only=A1,B1).''';

final RegExp _projectIdPattern = RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$');

/// The largest response body read; anything longer is cut.
const int _maxResponseBytes = 64 * 1024;

/// The service of every event: the console filters by it.
const String _service = 'error-reporting-probe';

Future<void> main(List<String> args) async {
  var yes = false;
  var printOnly = false;
  Set<String>? only;
  for (final arg in args) {
    if (arg == '--yes') {
      yes = true;
    } else if (arg == '--print') {
      printOnly = true;
    } else if (arg.startsWith('--only=')) {
      only = arg.substring('--only='.length).toUpperCase().split(',').toSet();
    } else if (arg == '--help' || arg == '-h') {
      stdout.writeln(_usage);
      return;
    } else {
      // Only the option's name: a credential passed here by mistake stays
      // hidden.
      final what = arg.startsWith('--')
          ? 'Unknown option ${arg.split('=').first}'
          : 'An argument that is not an option';
      stderr.writeln('$what.\n\n$_usage');
      exitCode = 64;
      return;
    }
  }

  final random = Random.secure();
  final tag = List<String>.generate(
    6,
    (_) => 'abcdefghjkmnpqrstuvwxyz23456789'[random.nextInt(31)],
  ).join();
  final now = DateTime.now().toUtc();
  final otherKey = Platform.environment['ER_OTHER_API_KEY'] ?? '';
  var cases = buildCases(tag, now, includeOtherKey: otherKey.isNotEmpty);
  if (only != null) {
    final unknown = only.difference(cases.map((c) => c.id).toSet());
    if (unknown.isNotEmpty) {
      stderr.writeln('Unknown case ids: ${unknown.join(', ')}.');
      exitCode = 64;
      return;
    }
    cases = [
      for (final c in cases)
        if (only.contains(c.id)) c,
    ];
  }

  if (printOnly) {
    for (final c in cases) {
      final size = utf8.encode(jsonEncode(c.body)).length;
      final shown = size > 8 * 1024
          ? '(a body of $size bytes; not shown)'
          : _pretty(c.body);
      stdout.writeln('${c.id}: ${c.title}\n$shown\n');
    }
    return;
  }

  final projectId = Platform.environment['ER_PROJECT_ID'] ?? '';
  final token = Platform.environment['ER_ACCESS_TOKEN'] ?? '';
  final apiKey = Platform.environment['ER_API_KEY'] ?? '';
  if (!_projectIdPattern.hasMatch(projectId)) {
    stderr.writeln(
      'ER_PROJECT_ID must be a Google Cloud project id: 6 to 30 lowercase '
      'letters, digits and hyphens, starting with a letter.',
    );
    exitCode = 64;
    return;
  }
  if ((token.isEmpty) == (apiKey.isEmpty)) {
    stderr.writeln(
      'Set exactly one of ER_ACCESS_TOKEN and ER_API_KEY (see --help).',
    );
    exitCode = 64;
    return;
  }
  for (final value in [token, apiKey, otherKey]) {
    if (value.contains(RegExp('[\\s&#?/"\']'))) {
      stderr.writeln(
        'A credential contains spaces, quotes or URL characters. Copy it '
        'again.',
      );
      exitCode = 64;
      return;
    }
  }
  final redact = _Redactor([token, apiKey, otherKey]);
  final credential = token.isNotEmpty
      ? 'an access token from ER_ACCESS_TOKEN (not shown)'
      : 'an API key from ER_API_KEY (not shown)';

  stdout.writeln('''
Error Reporting probe
  project      $projectId
  endpoint     https://clouderrorreporting.googleapis.com/v1beta1/projects/$projectId/events:report
  credential   $credential
  service      $_service
  version      $tag   (the run tag: filter the console by it)

It sends ${cases.length} events, one request each, a second apart:''');
  for (final c in cases) {
    stdout.writeln('  ${c.id.padRight(4)} ${c.title}');
  }

  if (!yes) {
    stdout.writeln(
      '\nNothing was sent. Run again with --yes to send. '
      '--print shows the request bodies.',
    );
    exitCode = 2;
    return;
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'firebase_dart_sdk-error-reporting-probe';
  final results = <String, int>{};
  try {
    for (final c in cases) {
      final key = c.useOtherKey ? otherKey : apiKey;
      final uri = Uri.https(
        'clouderrorreporting.googleapis.com',
        '/v1beta1/projects/$projectId/events:report',
        c.useOtherKey || key.isNotEmpty ? {'key': key} : null,
      );
      stdout.writeln('\n${c.id}: ${c.title}');
      final response = await _post(
        client,
        uri,
        c.body,
        // A key case never sends the token, so the key alone decides.
        accessToken: c.useOtherKey ? null : (token.isEmpty ? null : token),
        quotaProject: projectId,
      );
      if (response == null) {
        break;
      }
      results[c.id] = response.status;
      final ok = response.status >= 200 && response.status < 300;
      stdout.writeln(
        '   HTTP ${response.status}'
        '${ok ? '' : ': ${redact(response.body)}'}',
      );
      if (!ok && (response.status == 401 || response.status == 403)) {
        if (!c.useOtherKey && results.length == 1) {
          stderr.writeln(
            '   The first request was refused: check the credential, the '
            'role and that the Error Reporting API is enabled. Stopping.',
          );
          exitCode = 1;
          break;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } finally {
    client.close(force: true);
  }
  stdout.writeln(_whatToLookFor(tag, projectId, results, cases));
}

/// One event of the probe.
class ProbeCase {
  ProbeCase(this.id, this.title, this.body, {this.useOtherKey = false});

  final String id;
  final String title;
  final Map<String, Object?> body;

  /// Sent with ER_OTHER_API_KEY instead of the configured credential.
  final bool useOtherKey;
}

/// A Dart VM stack frame: `#N  member (uri:line:column)`.
class Frame {
  const Frame(this.member, this.uri, this.line, this.column);

  final String member;
  final String uri;
  final int line;
  final int column;

  String dart(int index) =>
      '#${index.toString().padRight(6)} $member ($uri:$line:$column)';

  String v8() => '    at $member ($uri:$line:$column)';
}

const List<Frame> _appFrames = [
  Frame(
    'NoteRepository.load',
    'package:probe_notes/src/repository.dart',
    42,
    7,
  ),
  Frame('NoteListModel.refresh', 'package:probe_notes/src/model.dart', 88, 12),
  Frame(
    'NoteListPage.initState.<fn>',
    'package:probe_notes/src/page.dart',
    31,
    5,
  ),
  Frame('main', 'package:probe_notes/main.dart', 12, 3),
];

const List<Frame> _otherAppFrames = [
  Frame('SyncQueue.drain', 'package:probe_notes/src/sync.dart', 117, 9),
  Frame('SyncService.run', 'package:probe_notes/src/sync.dart', 64, 5),
  Frame('main.<fn>', 'package:probe_notes/main.dart', 20, 7),
];

const List<Frame> _libraryFrames = [
  Frame('ListBase.first', 'dart:collection/list.dart', 79, 5),
  Frame('Iterable.first', 'dart:core/iterable.dart', 680, 7),
  Frame(
    'State.setState',
    'package:flutter/src/widgets/framework.dart',
    1192,
    30,
  ),
];

String _v8(String header, List<Frame> frames) =>
    [header, for (final f in frames) f.v8()].join('\n');

String _dart(String header, List<Frame> frames) => [
  header,
  for (var i = 0; i < frames.length; i++) frames[i].dart(i),
].join('\n');

Map<String, Object?> _location(Frame f) => {
  'filePath': f.uri,
  'lineNumber': f.line,
  'functionName': f.member,
};

/// The cases of tool/error_reporting_probe.md, labelled with [tag].
List<ProbeCase> buildCases(
  String tag,
  DateTime now, {
  required bool includeOtherKey,
}) {
  final eventTime = now.toIso8601String();
  Map<String, Object?> event(
    String message, {
    Map<String, Object?>? context,
    String? time,
  }) => {
    'eventTime': time ?? eventTime,
    'serviceContext': {'service': _service, 'version': tag},
    'message': message,
    if (context != null) 'context': context,
  };
  String header(String id, String text) =>
      'StateError: Bad state: $text [probe $tag $id]';
  final a1Frames = [..._libraryFrames.take(2), ..._appFrames];

  // A message of about [kib] KiB: the A1 trace with app frames repeated.
  String sized(String id, int kib) {
    final frames = <Frame>[...a1Frames];
    var i = 0;
    while (_v8(header(id, 'no element'), frames).length < kib * 1024) {
      final f = _appFrames[i % _appFrames.length];
      frames.add(Frame('${f.member}$i', f.uri, f.line + i, f.column));
      i++;
    }
    return _v8(header(id, 'no element'), frames);
  }

  final obfuscated = [
    '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***',
    'pid: 4242, tid: 4243, name 1.ui',
    "build_id: '8deece9b0e5bf1aa541b5a91e171282e'",
    'isolate_dso_base: 7f1c2a4000, vm_dso_base: 7f1c2a4000',
    'isolate_instructions: 7f1c2a9000, vm_instructions: 7f1c2a5000',
    '#00 abs 00007f1c2b0d1e2f virt 000000000002de2f _kDartIsolateSnapshotInstructions+0x28e2f',
    '#01 abs 00007f1c2b0c0a11 virt 000000000001ca11 _kDartIsolateSnapshotInstructions+0x17a11',
    '#02 abs 00007f1c2b0b7f03 virt 0000000000013f03 _kDartIsolateSnapshotInstructions+0xef03',
  ].join('\n');

  return [
    ProbeCase(
      'A1',
      'V8 format, dart: frames on top, no reportLocation',
      event(_v8(header('A1', 'no element'), a1Frames)),
    ),
    ProbeCase(
      'A2',
      'as A1 with another message: same group as A1 if grouping ignores the message',
      event(_v8(header('A2', 'too many elements'), a1Frames)),
    ),
    ProbeCase(
      'A3',
      'as A1 with other top frames: a new group if frames count',
      event(_v8(header('A3', 'no element'), _otherAppFrames)),
    ),
    ProbeCase(
      'A4',
      'as A1 with reportLocation (the first app frame)',
      event(
        _v8(header('A4', 'no element'), a1Frames),
        context: {'reportLocation': _location(_appFrames.first)},
      ),
    ),
    ProbeCase(
      'A5',
      'app frames under package:flutter and dart: frames',
      event(
        _v8(header('A5', 'no element'), [..._libraryFrames, ..._appFrames]),
      ),
    ),
    ProbeCase(
      'A6',
      'the app frames of A5 alone: same group as A5 if library frames are skipped',
      event(_v8(header('A6', 'no element'), _appFrames)),
    ),
    ProbeCase(
      'F1',
      'as A1 with "[fatal]" after the colon',
      event(_v8(header('F1', '[fatal] no element'), a1Frames)),
    ),
    ProbeCase(
      'F2',
      'as A1 with "[fatal]" before the type',
      event(_v8('[fatal] ${header('F2', 'no element')}', a1Frames)),
    ),
    ProbeCase(
      'B1',
      'raw Dart trace with reportLocation',
      event(
        _dart(header('B1', 'no element'), a1Frames),
        context: {'reportLocation': _location(_appFrames.first)},
      ),
    ),
    ProbeCase(
      'B2',
      'as B1 with another message: same group as B1?',
      event(
        _dart(header('B2', 'too many elements'), a1Frames),
        context: {'reportLocation': _location(_appFrames.first)},
      ),
    ),
    ProbeCase(
      'B3',
      'raw Dart trace without reportLocation: refused, or kept without a trace?',
      event(_dart(header('B3', 'no element'), a1Frames)),
    ),
    ProbeCase(
      'O1',
      'obfuscated trace with reportLocation',
      event(
        '${header('O1', 'no element')}\n$obfuscated',
        context: {
          'reportLocation': {
            'filePath': 'unknown',
            'lineNumber': 0,
            'functionName': '<obfuscated>',
          },
        },
      ),
    ),
    ProbeCase(
      'U1',
      'as A1 with context.user and httpRequest',
      event(
        _v8(header('U1', 'no element'), a1Frames),
        context: {
          'user': 'probe-user-$tag',
          'httpRequest': {
            'method': 'GET',
            'url': 'https://example.com/notes/42',
            'responseStatusCode': 500,
          },
        },
      ),
    ),
    for (final kib in [16, 64, 256])
      ProbeCase(
        'S$kib',
        'V8 format, about $kib KiB',
        event(sized('S$kib', kib)),
      ),
    ProbeCase(
      'T1',
      'eventTime 25 hours in the future: documented as refused',
      event(
        _v8(header('T1', 'no element'), a1Frames),
        time: now.add(const Duration(hours: 25)).toIso8601String(),
      ),
    ),
    if (includeOtherKey)
      ProbeCase(
        'K1',
        'as A1 with ER_OTHER_API_KEY, a key restricted to another API',
        event(_v8(header('K1', 'no element'), a1Frames)),
        useOtherKey: true,
      ),
  ];
}

class _Response {
  _Response(this.status, this.body);

  final int status;
  final String body;
}

/// Removes the credentials from server text before it is printed, and caps
/// its length.
class _Redactor {
  _Redactor(Iterable<String> secrets)
    : _secrets = [
        for (final s in secrets)
          if (s.isNotEmpty) s,
      ];

  final List<String> _secrets;

  String call(String text) {
    var out = text;
    for (final s in _secrets) {
      out = out.replaceAll(s, '<redacted>');
    }
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out.length <= 400 ? out : '${out.substring(0, 400)}…';
  }
}

/// Posts [body] as JSON and reads at most [_maxResponseBytes] of the answer.
/// Never prints the request URI, which may hold the key. Returns null after
/// printing what happened when the request failed.
Future<_Response?> _post(
  HttpClient client,
  Uri uri,
  Map<String, Object?> body, {
  required String? accessToken,
  required String quotaProject,
}) async {
  var sent = false;
  try {
    final request = await client.postUrl(uri);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    if (accessToken != null) {
      request.headers.set('authorization', 'Bearer $accessToken');
      // A user's token from gcloud needs a quota project.
      request.headers.set('x-goog-user-project', quotaProject);
    }
    final bytes = utf8.encode(jsonEncode(body));
    request.contentLength = bytes.length;
    request.add(bytes);
    sent = true;
    final response = await request.close().timeout(const Duration(seconds: 30));
    final received = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      received.add(chunk);
      if (received.length >= _maxResponseBytes) {
        break;
      }
    }
    final text = const Utf8Decoder(
      allowMalformed: true,
    ).convert(received.takeBytes());
    return _Response(response.statusCode, text);
  } on Object catch (error) {
    // The message of a socket or HTTP error can quote the URL; print only the
    // type.
    stderr.writeln(
      sent
          ? '   The request was sent but no answer came (${error.runtimeType}). '
                'It may have been recorded; look in the console before '
                'running again.'
          : '   Could not connect (${error.runtimeType}). Nothing was sent in '
                'this step.',
    );
    exitCode = 1;
    return null;
  }
}

String _whatToLookFor(
  String tag,
  String projectId,
  Map<String, int> results,
  List<ProbeCase> cases,
) {
  final statuses = [
    for (final c in cases)
      '   ${c.id.padRight(4)} ${results[c.id]?.toString() ?? 'not sent'}',
  ].join('\n');
  return '''

Statuses:
$statuses

What to look for: Google Cloud console > Error Reporting, project $projectId,
service $_service, version $tag. Each event's message ends in
"[probe $tag <case>]". Open each group and note which cases it holds.

Record for docs/error_reporting_spec.md, section 11:
   1. A1: is the trace shown as parsed frames (a stack with file and line),
      or as plain text?
   2. Is A2 in A1's group (the message is ignored)? Is A3 in a group of its
      own (frames count)? Are B1 and B2 in one group?
   3. Is A4 in A1's group, and does reportLocation change what is shown?
   4. Are A5 and A6 in one group (library frames skipped)?
   5. Are F1 and F2 in A1's group, or apart from it?
   6. Statuses of S16, S64 and S256: the size the API accepts, and the
      answer above it.
   7. U1: where the user and the request appear.
   8. B3 and T1: status and message. K1 (if sent): status and message.
   Also: O1 as shown; the date; the run tag $tag.''';
}

String _pretty(Object? json) =>
    const JsonEncoder.withIndent('  ').convert(json);
