// The Analytics reporting probe. It answers one question before the Analytics
// client is built: does Google Analytics report events that carry a client_id
// generated outside gtag.js? See tool/analytics_probe.md and
// docs/analytics_protocol.md, sections 5 and 10.
//
// It sends a handful of events and one user property to a GA4 web stream:
// first to the validation server (/debug/mp/collect, which records nothing),
// then to the collection endpoint (/mp/collect). With --control-client-id it
// also sends the same events under a client_id taken from gtag.js, so that a
// negative result can be told apart from a wrong secret or stream. It sends
// nothing without --yes. The API secret comes from the environment and is
// never printed: server text is redacted before it is shown.
//
// From the repository root:
//
//   export GA_MEASUREMENT_ID=G-XXXXXXXXXX
//   read -rs GA_API_SECRET && export GA_API_SECRET
//   dart tool/analytics_probe.dart              # prints the plan, sends nothing
//   dart tool/analytics_probe.dart --yes        # sends
//
// Only dart:io and dart:convert, so it runs with a plain `dart` and no pub get.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const String _usage = '''
Usage: dart tool/analytics_probe.dart [--yes] [--control-client-id=ID]
                                      [--region=global|eu] [--print]

Environment:
  GA_MEASUREMENT_ID  the Measurement ID of a GA4 web data stream (G-...)
  GA_API_SECRET      a Measurement Protocol API secret of that stream

--control-client-id  a client id that gtag.js used on that stream (the _ga
                     cookie of a page tagged with it); the same events are
                     sent under it as a positive control
Without --yes it prints what it would send and sends nothing.
--print prints the request bodies and exits; it needs no secret.''';

final RegExp _measurementIdPattern = RegExp(r'^G-[A-Z0-9]{4,20}$');
final RegExp _controlClientIdPattern = RegExp(
  r'^(GA1\.\d+\.)?[1-9]\d{0,19}\.[1-9]\d{0,19}$',
);

/// The largest response body read; anything longer is cut.
const int _maxResponseBytes = 64 * 1024;

Future<void> main(List<String> args) async {
  var yes = false;
  var printOnly = false;
  var region = 'global';
  String? controlClientId;
  for (final arg in args) {
    if (arg == '--yes') {
      yes = true;
    } else if (arg == '--print') {
      printOnly = true;
    } else if (arg == '--region=eu' || arg == '--region=global') {
      region = arg.substring('--region='.length);
    } else if (arg.startsWith('--control-client-id=')) {
      controlClientId = arg.substring('--control-client-id='.length);
    } else if (arg == '--help' || arg == '-h') {
      stdout.writeln(_usage);
      return;
    } else {
      // Only the option's name: a secret passed here by mistake stays hidden.
      final what = arg.startsWith('--')
          ? 'Unknown option ${arg.split('=').first}'
          : 'An argument that is not an option';
      stderr.writeln('$what.\n\n$_usage');
      exitCode = 64;
      return;
    }
  }
  if (controlClientId != null &&
      !_controlClientIdPattern.hasMatch(controlClientId)) {
    stderr.writeln(
      '--control-client-id must be a client id from gtag.js: the value of the '
      '_ga cookie (GA1.1.123.456) or its last two numbers (123.456).',
    );
    exitCode = 64;
    return;
  }

  final host = region == 'eu'
      ? 'region1.google-analytics.com'
      : 'www.google-analytics.com';
  final random = Random.secure();
  // Every event is dated within the two minutes before now, so a clock that
  // runs a little fast still dates them in the past, and the session starts
  // at the first of them.
  final start = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
  final run = _Run(
    // The documented client_id format: two positive numbers joined by a
    // period (docs/analytics_protocol.md, section 3). The second one is the
    // time of first use in seconds, as in gtag.js.
    clientId: '${1 + random.nextInt(0x7fffffff)}.${_seconds(start)}',
    controlClientId: controlClientId,
    sessionId: _seconds(start),
    tag: List<String>.generate(
      6,
      (_) => 'abcdefghjkmnpqrstuvwxyz23456789'[random.nextInt(31)],
    ).join(),
    start: start,
  );
  final control = run.controlClientId;

  if (printOnly) {
    stdout.writeln('Validation body:\n${_pretty(run.validationBody())}\n');
    stdout.writeln('DebugView body:\n${_pretty(run.debugBody())}\n');
    stdout.writeln('Reporting body:\n${_pretty(run.reportingBody())}');
    if (control != null) {
      stdout.writeln('\nControl body:\n${_pretty(run.controlBody())}');
    }
    stdout.writeln(
      '\nValidation-only checks (titles and sizes; bodies not shown):',
    );
    for (final check in run.informationalChecks()) {
      final size = utf8.encode(jsonEncode(check.body)).length;
      stdout.writeln('  ${check.title}: $size bytes');
    }
    return;
  }

  final measurementId = Platform.environment['GA_MEASUREMENT_ID'] ?? '';
  final apiSecret = Platform.environment['GA_API_SECRET'] ?? '';
  if (!_measurementIdPattern.hasMatch(measurementId)) {
    stderr.writeln(
      'GA_MEASUREMENT_ID must be the Measurement ID of a web data stream '
      '(G- followed by letters and digits).',
    );
    exitCode = 64;
    return;
  }
  if (apiSecret.length < 8 || apiSecret.contains(RegExp('[\\s&#?/"\']'))) {
    stderr.writeln(
      'GA_API_SECRET must be set to a Measurement Protocol API secret of that '
      'stream (Admin > Data streams > the stream > Measurement Protocol API '
      'secrets), without spaces or quotes.',
    );
    exitCode = 64;
    return;
  }
  final redact = _Redactor(apiSecret);

  final controlLine = control == null
      ? 'none: a negative result will be inconclusive'
      : '$control   (from gtag.js)';
  final controlStep = control == null
      ? ''
      : '\n  4. /mp/collect, the same 3 events under the control client_id;';
  stdout.writeln('''
Analytics reporting probe
  stream       $measurementId
  endpoint     https://$host/mp/collect (validation: /debug/mp/collect)
  api secret   from GA_API_SECRET (not shown)
  client_id    ${run.clientId}   (generated here, never used by gtag.js)
  control      $controlLine
  session_id   ${run.sessionId}
  run tag      ${run.tag}   (the probe_run parameter of every event)

It sends:
  1. the validation server, strict mode: nothing is recorded;
  1b-1j. the validation server again, once per open question of protocol section 10 (informational; see
     tool/analytics_probe.md);
  2. /mp/collect, ${run.debugEventNames.length} events with debug_mode, for DebugView;
  3. /mp/collect, ${run.reportingEventNames.length} events without debug_mode, for Realtime and the reports;$controlStep
with the user property probe_kind=measurement_protocol.''');

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
    ..userAgent = 'firebase_dart_sdk-analytics-probe';
  Uri endpoint(String path) => Uri.https(host, path, <String, String>{
    'measurement_id': measurementId,
    'api_secret': apiSecret,
  });
  var reachedCollect = false;
  try {
    stdout.writeln('\n1. Validation server');
    final toValidate = <Map<String, Object?>>[
      run.validationBody(),
      if (control != null) run.controlBody(validation: true),
    ];
    for (final body in toValidate) {
      final validation = await _post(
        client,
        endpoint('/debug/mp/collect'),
        body,
        recordsData: false,
      );
      if (validation == null) {
        return;
      }
      final messages = validation.status == 200
          ? _validationMessages(validation.body, redact)
          : null;
      if (messages == null) {
        stderr.writeln(
          '   HTTP ${validation.status} (${redact(validation.contentType)}), '
          'not a validation response. Stopping before /mp/collect.',
        );
        exitCode = 1;
        return;
      }
      if (messages.isNotEmpty) {
        stderr.writeln(
          '   The validation server refused the body. Stopping before '
          '/mp/collect.',
        );
        for (final message in messages) {
          stderr.writeln('   - $message');
        }
        exitCode = 1;
        return;
      }
    }
    stdout.writeln('   HTTP 200, no validation messages.');

    // Informational: the validation server records nothing, and these never stop the run. Each answers a
    // question of docs/analytics_protocol.md, section 10.
    for (final check in run.informationalChecks()) {
      stdout.writeln('\n${check.title}');
      final answer = await _post(
        client,
        endpoint('/debug/mp/collect'),
        check.body,
        recordsData: false,
      );
      final messages = answer == null || answer.status != 200
          ? null
          : _validationMessages(answer.body, redact);
      if (messages == null) {
        stdout.writeln(
          answer == null
              ? '   No answer; continuing.'
              : '   HTTP ${answer.status}, not a validation response; continuing.',
        );
      } else if (messages.isEmpty) {
        stdout.writeln('   Accepted, no validation messages.');
      } else {
        stdout.writeln('   Refused, with these messages:');
        for (final message in messages) {
          stdout.writeln('   - $message');
        }
      }
    }

    final steps = <(String, Map<String, Object?>)>[
      ('2. /mp/collect, for DebugView', run.debugBody()),
      ('3. /mp/collect, for Realtime and the reports', run.reportingBody()),
      if (control != null)
        ('4. /mp/collect, under the control client_id', run.controlBody()),
    ];
    for (final (title, body) in steps) {
      stdout.writeln('\n$title');
      final response = await _post(
        client,
        endpoint('/mp/collect'),
        body,
        recordsData: true,
      );
      if (response == null) {
        // Sent but unanswered: it may have been recorded.
        reachedCollect = _maybeRecorded;
        break;
      }
      reachedCollect = true;
      if (!_ok(response, redact)) {
        break;
      }
    }
  } finally {
    client.close(force: true);
  }

  // Printed whenever /mp/collect may have recorded something, also after a
  // later step failed, so the run is checked before anyone runs it again.
  if (reachedCollect) {
    stdout.writeln(_whatToLookFor(run, measurementId, DateTime.now().toUtc()));
  }
}

/// Set when a request to an endpoint that records data was sent but got no
/// answer.
var _maybeRecorded = false;

/// One probe run: the identifiers it reports under and the bodies it sends.
class _Run {
  _Run({
    required this.clientId,
    required this.controlClientId,
    required this.sessionId,
    required this.tag,
    required this.start,
  });

  final String clientId;
  final String? controlClientId;
  final int sessionId;
  final String tag;

  /// The time of the first event and the start of the session.
  final DateTime start;

  final List<String> debugEventNames = const <String>[
    'probe_start',
    'page_view',
    'level_up',
  ];

  final List<String> reportingEventNames = const <String>[
    'probe_report',
    'page_view',
    'select_content',
  ];

  Map<String, Object?> _event(
    String name,
    int offsetMs,
    String arm, {
    required bool debug,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final at = start.add(Duration(milliseconds: offsetMs));
    return <String, Object?>{
      'name': name,
      'timestamp_micros': at.microsecondsSinceEpoch,
      'params': <String, Object?>{
        'session_id': sessionId,
        'engagement_time_msec': 1000 + offsetMs % 1000,
        'probe_run': tag,
        'probe_arm': arm,
        if (debug) 'debug_mode': true,
        ...extra,
      },
    };
  }

  List<Map<String, Object?>> _events({
    required bool debug,
    String arm = 'generated',
  }) {
    final base = debug ? 0 : 5000;
    return <Map<String, Object?>>[
      _event(debug ? 'probe_start' : 'probe_report', base, arm, debug: debug),
      _event(
        'page_view',
        base + 1200,
        arm,
        debug: debug,
        extra: <String, Object?>{
          'page_title': 'Probe home',
          'page_location': 'app://analytics-probe/home',
          'screen_class': 'ProbeScreen',
        },
      ),
      if (debug)
        _event(
          'level_up',
          base + 2500,
          arm,
          debug: debug,
          extra: <String, Object?>{'level': 3, 'character': 'probe'},
        )
      else
        _event(
          'select_content',
          base + 2500,
          arm,
          debug: debug,
          extra: <String, Object?>{
            'content_type': 'probe',
            'content_id': 'probe-1',
          },
        ),
    ];
  }

  Map<String, Object?> _body(
    String id,
    List<Map<String, Object?>> events, {
    bool validation = false,
  }) => <String, Object?>{
    'client_id': id,
    'user_properties': <String, Object?>{
      'probe_kind': <String, Object?>{'value': 'measurement_protocol'},
    },
    // No `device`: in strict mode the validation server requires fields of it
    // that a program cannot read (model, browser), and refuses a partial one.
    'events': events,
    if (validation) 'validation_behavior': 'ENFORCE_RECOMMENDATIONS',
  };

  /// Both batches of the generated client_id in one body, in strict mode,
  /// for the validation server.
  Map<String, Object?> validationBody() => _body(
    clientId,
    <Map<String, Object?>>[..._events(debug: true), ..._events(debug: false)],
    validation: true,
  );

  Map<String, Object?> debugBody() => _body(clientId, _events(debug: true));

  Map<String, Object?> reportingBody() =>
      _body(clientId, _events(debug: false));

  /// One body per open question of docs/analytics_protocol.md, section 10, for the validation server only,
  /// in strict mode. Each title says what it asks.
  List<({String title, Map<String, Object?> body})> informationalChecks() {
    Map<String, Object?> one(
      String arm, {
      String name = 'probe_report',
      Map<String, Object?> extra = const <String, Object?>{},
    }) => _body(clientId, <Map<String, Object?>>[
      _event(name, 0, arm, debug: false, extra: extra),
    ], validation: true);

    String location(int length) {
      const prefix = 'https://probe.example/';
      return prefix + 'a' * (length - prefix.length);
    }

    return <({String title, Map<String, Object?> body})>[
      (
        title: '1b. Question 6: a complete device block (all nine fields)',
        body: <String, Object?>{
          ...one('device_check'),
          'device': <String, Object?>{
            'category': 'desktop',
            'language': _language(),
            'screen_resolution': '1920x1080',
            'operating_system': _operatingSystem(),
            'operating_system_version': '1.0',
            'model': 'Probe',
            'brand': 'Probe',
            'browser': 'Probe',
            'browser_version': '1.0',
          },
        },
      ),
      (
        title: '1c. Question 7: the A/B testing user property firebase_exp_1',
        body: () {
          final body = one('experiment_check');
          return <String, Object?>{
            ...body,
            'user_properties': <String, Object?>{
              ...body['user_properties']! as Map<String, Object?>,
              'firebase_exp_1': <String, Object?>{'value': '1'},
            },
          };
        }(),
      ),
      for (final length in <int>[100, 101, 1000])
        (
          title:
              '1${switch (length) {
                100 => 'd',
                101 => 'e',
                _ => 'f',
              }}. Question 3: a page_location of '
              '$length characters',
          body: one(
            'location_$length',
            name: 'page_view',
            extra: <String, Object?>{
              'page_title': 'Probe',
              'page_location': location(length),
            },
          ),
        ),
      (
        title:
            '1g. Question 4, control: a text value of 101 ASCII characters (expected: refused)',
        body: one(
          'ascii_101',
          extra: <String, Object?>{'probe_text': 'a' * 101},
        ),
      ),
      (
        title:
            '1h. Question 4: a text value of 100 non-ASCII characters (\u0103), 200 UTF-8 bytes, 600 '
            'percent-encoded',
        body: one(
          'non_ascii_100',
          extra: <String, Object?>{'probe_text': '\u0103' * 100},
        ),
      ),
      for (final (letter, size) in <(String, int)>[
        ('i', 130000),
        ('j', 133120),
      ])
        (
          title: '1$letter. Question 5: a body of exactly $size bytes',
          body: sizedBody(size),
        ),
    ];
  }

  /// A strict-mode body of exactly [bytes] bytes of UTF-8 JSON: `view_item_list` events whose items carry
  /// the padding, at most 200 items an event.
  Map<String, Object?> sizedBody(int bytes) {
    Map<String, Object?> build(int items, int extra) {
      final events = <Map<String, Object?>>[];
      var left = extra;
      for (var first = 0; first < items || events.isEmpty; first += 200) {
        events.add(
          _event(
            'view_item_list',
            events.length,
            'size_$bytes',
            debug: false,
            extra: <String, Object?>{
              'items': <Map<String, Object?>>[
                for (var i = first; i < items && i < first + 200; i++)
                  () {
                    final grow = left < 50 ? left : 50;
                    left -= grow;
                    return <String, Object?>{
                      'item_id': 'p${i.toString().padLeft(4, '0')}',
                      'item_name': 'n' * (50 + grow),
                    };
                  }(),
              ],
            },
          ),
        );
      }
      return _body(clientId, events, validation: true);
    }

    int size(Map<String, Object?> body) => utf8.encode(jsonEncode(body)).length;

    // An estimate from the size of one item, then a few steps to the largest count that fits.
    final empty = size(build(0, 0));
    final perItem = size(build(1, 0)) - empty;
    var items = (bytes - empty) ~/ perItem;
    while (items > 0 && size(build(items, 0)) > bytes) {
      items--;
    }
    while (size(build(items + 1, 0)) <= bytes) {
      items++;
    }
    final body = build(items, bytes - size(build(items, 0)));
    final actual = size(body);
    if (actual != bytes) {
      throw StateError('Could not build a body of $bytes bytes (got $actual).');
    }
    return body;
  }

  /// The reporting events again, under the client_id from gtag.js.
  Map<String, Object?> controlBody({bool validation = false}) => _body(
    controlClientId!,
    _events(debug: false, arm: 'control'),
    validation: validation,
  );
}

class _Response {
  _Response(this.status, this.contentType, this.body);

  final int status;
  final String contentType;
  final String body;
}

/// Removes the secret, in every form a server could echo it, and control
/// characters from text before it is printed.
class _Redactor {
  _Redactor(String secret)
    : _forms = <String>{
        secret,
        Uri.encodeQueryComponent(secret),
        Uri.encodeComponent(secret),
        Uri.encodeFull(secret),
        const HtmlEscape().convert(secret),
      }.where((form) => form.isNotEmpty).toList();

  final List<String> _forms;

  String call(String text) {
    var out = text;
    for (final form in _forms) {
      out = out.replaceAll(form, '<api secret>');
    }
    out = out.replaceAll(RegExp(r'[\x00-\x08\x0b-\x1f\x7f\x9b]'), '');
    return out.length <= 300 ? out : '${out.substring(0, 300)}…';
  }
}

/// Posts [body] as JSON and reads at most [_maxResponseBytes] of the answer.
/// Never prints the request URI, which holds the secret. Returns null after
/// printing what happened when the request failed. [recordsData] says whether
/// the endpoint keeps what it receives, which decides the advice after a
/// failure once the body has been sent.
Future<_Response?> _post(
  HttpClient client,
  Uri uri,
  Map<String, Object?> body, {
  required bool recordsData,
}) async {
  var sent = false;
  try {
    final request = await client.postUrl(uri);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
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
    return _Response(
      response.statusCode,
      response.headers.contentType?.mimeType ?? 'no content type',
      text,
    );
  } on Object catch (error) {
    // The message of a socket or HTTP error can quote the URL; print only the
    // type.
    if (!sent) {
      stderr.writeln(
        '   Could not connect (${error.runtimeType}). Nothing was sent in '
        'this step. Check the network and run again.',
      );
    } else if (recordsData) {
      stderr.writeln(
        '   The request was sent but no answer came (${error.runtimeType}). '
        'Google Analytics may have recorded it. Do not run the probe again '
        'yet: look in DebugView and Realtime first (the checklist below).',
      );
      _maybeRecorded = true;
    } else {
      stderr.writeln(
        '   The validation request was sent but no answer came '
        '(${error.runtimeType}). Nothing is recorded there; run again.',
      );
    }
    exitCode = 1;
    return null;
  }
}

bool _ok(_Response response, _Redactor redact) {
  if (response.status >= 200 && response.status < 300) {
    stdout.writeln(
      '   HTTP ${response.status}. Accepted for delivery; the endpoint '
      'answers 2xx even for data it does not process.',
    );
    return true;
  }
  stderr.writeln(
    '   HTTP ${response.status} (${redact(response.contentType)}). Stopping; '
    'the documentation says not to retry a refused request.',
  );
  exitCode = 1;
  return false;
}

/// The validation messages of a /debug/mp/collect response, as printable
/// lines, or null when [body] is not such a response.
List<String>? _validationMessages(String body, _Redactor redact) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map || decoded['validationMessages'] is! List) {
    return null;
  }
  return <String>[
    for (final message in decoded['validationMessages'] as List)
      if (message is Map)
        redact(
          '${message['validationCode']} at ${message['fieldPath']}: '
          '${message['description']}',
        )
      else
        redact('$message'),
  ];
}

String _whatToLookFor(_Run run, String measurementId, DateTime sentAt) {
  final control = run.controlClientId;
  final controlNote = control == null
      ? '''
   No control was sent. If nothing appears, the result is inconclusive: the
   validation server does not check the secret or the stream, and /mp/collect
   answers 2xx either way. Run again with --control-client-id before
   recording a negative result.'''
      : '''
   The control client_id ($control) sent probe_report, page_view and
   select_content with probe_arm=control. If the control events appear and
   the generated ones (probe_arm=generated) do not, the generated client_id
   is the cause. If neither appears, check the secret and the stream.''';
  return '''

Sent at ${sentAt.toIso8601String()}. What to look for, in the property of $measurementId:

A. DebugView (Admin > DebugView), within a minute or two:
   a device appears; its events are ${run.debugEventNames.join(', ')},
   each with probe_run=${run.tag}, and the user property probe_kind.
   If the property has an active "Developer traffic" data filter, these
   events are kept out of the reports but still show here.

B. Realtime (Reports > Realtime), within a few minutes:
   "Event count by Event name" lists ${run.reportingEventNames.join(', ')}
   (and the DebugView events unless a filter removes them), and the
   user count is at least ${control == null ? 1 : 2}. Note which country the users appear in,
   if any: the probe sends no user_location and no ip_override.
$controlNote

C. Standard reports, 24 to 48 hours later:
   - Reports > Engagement > Events: probe_report and select_content.
   - Reports > Engagement > Pages and screens: the page title "Probe home".
   - Reports > Tech > Overview: whatever Google Analytics derives; the
     probe sends no device block.
   - Reports > User > Demographics: the country, or "(not set)".
   probe_run, probe_arm and probe_kind appear in reports only after they are
   registered as custom dimensions (event-scoped and user-scoped); DebugView
   shows them without that.

Record for docs/analytics_protocol.md, section 10:
   1. Did the events of the generated client_id appear in DebugView? In
      Realtime? In the standard reports? And those of the control?
   2. Which country, if any, was reported?
   3. The results of steps 1b to 1j, each under its question of section 10
      (3: page_location, 4: non-ASCII, 5: body size, 6: device, 7: firebase_exp_).
   Also the date, the run tag ${run.tag}, and whether a data filter was active.''';
}

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

String _operatingSystem() => switch (Platform.operatingSystem) {
  'macos' => 'MacOS',
  'windows' => 'Windows',
  'linux' => 'Linux',
  final other => other,
};

/// The two-letter ISO 639-1 language of the locale, without its region, so
/// that the request carries no hint of a country; `en` when it cannot be read.
String _language() {
  final match = RegExp(
    r'^([a-zA-Z]{2})(?![a-zA-Z])',
  ).firstMatch(Platform.localeName);
  return match == null ? 'en' : match.group(1)!.toLowerCase();
}

String _pretty(Object? json) =>
    const JsonEncoder.withIndent('  ').convert(json);
