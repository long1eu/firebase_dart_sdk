import 'dart:convert';

import 'package:http/http.dart' as http;

/// Set to `1` to print, for every Identity Toolkit call, the method, the HTTP
/// status and the names of the fields of the answer (never their values).
const String logAnswersVariable = 'AUTH_HARNESS_LOG_ANSWERS';

/// An [http.Client] that prints what [describeAnswer] says about the answers
/// of the Identity Toolkit API; other requests pass through unread.
class AnswerLoggingClient extends http.BaseClient {
  AnswerLoggingClient(this._inner, this._log);

  final http.Client _inner;
  final void Function(String line) _log;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.StreamedResponse response = await _inner.send(request);
    if (request.url.host != 'identitytoolkit.googleapis.com') {
      return response;
    }
    final List<int> bytes = await response.stream.toBytes();
    _log(
      '  [answer] ${request.url.pathSegments.last} ${response.statusCode}: '
      '${describeAnswer(bytes)}',
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

/// The field names of a JSON answer, sorted; for `mfaInfo` the field names of
/// each entry, and for `error` the backend's message (a code such as
/// `INVALID_CODE`). No other value is included.
String describeAnswer(List<int> body) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(body));
  } on FormatException {
    return 'not JSON';
  }
  if (json is! Map<String, Object?>) {
    return 'not a JSON object';
  }
  final Map<String, Object?> answer = json;
  String fieldsOf(Object? entry) => entry is Map<String, Object?>
      ? (entry.keys.toList()..sort()).join(' ')
      : '?';
  return (answer.keys.toList()..sort())
      .map((String key) {
        final Object? value = answer[key];
        if (key == 'error' && value is Map<String, Object?>) {
          return 'error(${value['message']})';
        }
        if (key == 'mfaInfo' && value is List<Object?>) {
          return 'mfaInfo[${value.map(fieldsOf).join(' | ')}]';
        }
        return key;
      })
      .join(', ');
}
