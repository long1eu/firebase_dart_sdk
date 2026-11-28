// A loopback server for the tests of firebase_ai_dart (tool/test_browser_ai.sh starts it, and
// the step 5 probe of the FlutterFire client uses it). It listens on 127.0.0.1 on a port the
// system picks and prints that port, alone on one line, as the first line of its output. It
// holds no state and logs to stderr.
//
// <M> stands for both model path prefixes:
//   /v1beta/projects/demo/models/
//   /v1beta/projects/demo/locations/global/publishers/google/models/
//
//   OPTIONS <any path>                      204
//   POST <M>ok:generateContent              200, one reply "hello"
//   POST <M>ok:countTokens                  200, {"totalTokens":3}
//   POST <M>ok:streamGenerateContent?alt=sse
//       five events, one per second; the last one finishes
//   POST <M>split:streamGenerateContent?alt=sse
//       one event in three flushes, split inside a UTF-8 sequence and between the CR and
//       the LF of the closing CR LF CR LF
//   POST <M>keepalive:streamGenerateContent?alt=sse
//       one event, then ": ping" every second
//   POST <M>echo:generateContent            200, the request's header names and values as text
//   POST <M>bad-request:generateContent     400 INVALID_ARGUMENT
//   POST <M>html:generateContent            404, text/html
//   POST <M>disabled:generateContent        403, SERVICE_DISABLED of the AI Logic service
//   POST <M>other-disabled:generateContent  403, SERVICE_DISABLED of another service
//   POST <M>quota:generateContent           429, RetryInfo 7s and Retry-After: 9
//   POST <M>redirect:generateContent        302 to the ok path of the same backend
//
// Any other request gets 404.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The headers of the client (section 3.3 of the specification), plus the ones a browser adds.
const String _allowedHeaders =
    'Content-Type, Accept, Authorization, X-Goog-Api-Key, X-Goog-Api-Client, '
    'X-Firebase-AppId, X-Firebase-AppCheck';

final RegExp _modelPath = RegExp(
  r'^(/v1beta/projects/demo/(?:locations/global/publishers/google/)?models/)'
  r'([a-z-]+):(generateContent|countTokens|streamGenerateContent)$',
);

const Map<String, Object?> _usage = <String, Object?>{
  'promptTokenCount': 1,
  'candidatesTokenCount': 1,
  'totalTokenCount': 2,
};

Future<void> main() async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  stdout.writeln(server.port);
  await stdout.flush();
  await for (final HttpRequest request in server) {
    unawaited(_serve(request));
  }
}

Future<void> _serve(HttpRequest request) async {
  try {
    await _handle(request);
  } on Object catch (error) {
    stderr.writeln(
      'fake server: ${request.method} ${request.uri.path}: $error',
    );
    try {
      await request.response.close();
    } on Object catch (closeError) {
      stderr.writeln('fake server: closing the response failed: $closeError');
    }
  }
}

Future<void> _handle(HttpRequest request) async {
  final HttpResponse response = request.response;
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
    ..set('Access-Control-Allow-Headers', _allowedHeaders)
    ..set('Access-Control-Expose-Headers', 'Retry-After');
  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    await response.close();
    return;
  }
  final RegExpMatch? match = _modelPath.firstMatch(request.uri.path);
  if (request.method != 'POST' || match == null) {
    await _notFound(response);
    return;
  }
  final String prefix = match.group(1)!;
  final String name = match.group(2)!;
  final String task = match.group(3)!;
  final bool sse = request.uri.queryParameters['alt'] == 'sse';
  await request.drain<void>();
  switch ((name, task)) {
    case ('ok', 'generateContent'):
      await _json(response, HttpStatus.ok, _reply('hello'));
    case ('ok', 'countTokens'):
      await _json(response, HttpStatus.ok, <String, Object?>{'totalTokens': 3});
    case ('ok', 'streamGenerateContent') when sse:
      await _stream(response);
    case ('split', 'streamGenerateContent') when sse:
      await _split(response);
    case ('keepalive', 'streamGenerateContent') when sse:
      await _keepAlive(response);
    case ('echo', 'generateContent'):
      await _echo(request, response);
    default:
      await _failure(response, prefix, name, task);
  }
}

Future<void> _failure(
  HttpResponse response,
  String prefix,
  String name,
  String task,
) async {
  if (task != 'generateContent') {
    await _notFound(response);
    return;
  }
  switch (name) {
    case 'bad-request':
      await _json(
        response,
        HttpStatus.badRequest,
        _error(400, 'bad', 'INVALID_ARGUMENT'),
      );
    case 'html':
      response.statusCode = HttpStatus.notFound;
      response.headers.contentType = ContentType.html;
      response.write('<html>not found</html>');
      await response.close();
    case 'disabled':
      await _json(
        response,
        HttpStatus.forbidden,
        _disabled('firebasevertexai.googleapis.com'),
      );
    case 'other-disabled':
      await _json(
        response,
        HttpStatus.forbidden,
        _disabled('firebaseappcheck.googleapis.com'),
      );
    case 'quota':
      response.headers.set('Retry-After', '9');
      await _json(
        response,
        HttpStatus.tooManyRequests,
        _error(
          429,
          'quota',
          'RESOURCE_EXHAUSTED',
          details: <Object?>[
            <String, Object?>{
              '@type': 'type.googleapis.com/google.rpc.RetryInfo',
              'retryDelay': '7s',
            },
          ],
        ),
      );
    case 'redirect':
      response.statusCode = HttpStatus.found;
      response.headers.set('Location', '${prefix}ok:generateContent');
      await response.close();
    default:
      await _notFound(response);
  }
}

Map<String, Object?> _reply(String text) => <String, Object?>{
  'candidates': <Object?>[
    <String, Object?>{
      'content': <String, Object?>{
        'role': 'model',
        'parts': <Object?>[
          <String, Object?>{'text': text},
        ],
      },
      'finishReason': 'STOP',
    },
  ],
  'usageMetadata': _usage,
};

Map<String, Object?> _error(
  int code,
  String message,
  String status, {
  List<Object?>? details,
}) => <String, Object?>{
  'error': <String, Object?>{
    'code': code,
    'message': message,
    'status': status,
    'details': ?details,
  },
};

Map<String, Object?> _disabled(String service) => _error(
  403,
  'disabled',
  'PERMISSION_DENIED',
  details: <Object?>[
    <String, Object?>{
      '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
      'reason': 'SERVICE_DISABLED',
      'domain': 'googleapis.com',
      'metadata': <String, Object?>{'service': service},
    },
  ],
);

Future<void> _notFound(HttpResponse response) async {
  response.statusCode = HttpStatus.notFound;
  await response.close();
}

Future<void> _json(HttpResponse response, int status, Object body) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

Future<void> _echo(HttpRequest request, HttpResponse response) async {
  final Map<String, String> headers = <String, String>{};
  request.headers.forEach((String name, List<String> values) {
    headers[name.toLowerCase()] = values.join(', ');
  });
  await _json(response, HttpStatus.ok, _reply(jsonEncode(headers)));
}

void _startEventStream(HttpResponse response) {
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType('text', 'event-stream');
  response.bufferOutput = false;
}

Future<void> _stream(HttpResponse response) async {
  _startEventStream(response);
  final Future<void> closed = response.done.then(
    (Object? _) {},
    onError: (Object _) {},
  );
  bool open = true;
  unawaited(closed.whenComplete(() => open = false));
  for (int i = 0; i < 5 && open; i++) {
    final Map<String, Object?> event = <String, Object?>{
      'candidates': <Object?>[
        <String, Object?>{
          'content': <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{'text': '$i'},
            ],
          },
          if (i == 4) 'finishReason': 'STOP',
        },
      ],
      if (i == 4) 'usageMetadata': _usage,
    };
    response.write('data: ${jsonEncode(event)}\n\n');
    await response.flush();
    if (i < 4) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  if (open) {
    await response.close();
  }
}

Future<void> _split(HttpResponse response) async {
  _startEventStream(response);
  final String text = jsonEncode(_reply('café'));
  final List<int> bytes = utf8.encode('data: $text\r\n\r\n');
  // The two bytes of the e with an acute accent, then the first CR of the terminator.
  final int accent = bytes.indexOf(0xC3);
  final int firstCr = bytes.lastIndexOf(0x0D) - 2;
  final List<List<int>> parts = <List<int>>[
    bytes.sublist(0, accent + 1),
    bytes.sublist(accent + 1, firstCr + 1),
    bytes.sublist(firstCr + 1),
  ];
  for (int i = 0; i < parts.length; i++) {
    response.add(parts[i]);
    await response.flush();
    if (i < parts.length - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  await response.close();
}

Future<void> _keepAlive(HttpResponse response) async {
  _startEventStream(response);
  bool open = true;
  unawaited(
    response.done
        .then((Object? _) {}, onError: (Object _) {})
        .whenComplete(() => open = false),
  );
  response.write('data: ${jsonEncode(_reply('first'))}\n\n');
  await response.flush();
  while (open) {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!open) {
      break;
    }
    try {
      response.write(': ping\n\n');
      await response.flush();
    } on Object catch (error) {
      stderr.writeln('fake server: keepalive ended: $error');
      break;
    }
  }
}
