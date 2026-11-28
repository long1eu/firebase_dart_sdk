/// The handler of the relay: it takes a `ReportedErrorEvent` that `relayGuard` let through, rebuilds it from the
/// fields it trusts, and forwards it to `projects.events.report`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart';

/// The largest `message` forwarded, in characters.
const int maxMessageLength = 32 * 1024;

/// The longest field of the request context forwarded, in characters.
const int maxFieldLength = 2048;

/// A handler that forwards each event to Error Reporting in [projectId].
///
/// * Only the services in [services] are accepted: the `serviceContext.service` of the event must be one of
///   them, so a caller cannot fill the console with services of its own. The version must match
///   [versionPattern] (by default a release such as `1.4.0`, at most 32 characters).
/// * The event is rebuilt from `eventTime` (dropped when it is not a time of the last 30 days or the next
///   hour), `message` (capped), `serviceContext`, `context.reportLocation` and `context.httpRequest` (fields
///   capped). Anything else is left out.
/// * `context.user` is the uid of the verified ID token, never what the caller wrote: without a signed-in user
///   there is no user.
/// * [accessToken] gives an OAuth access token of a service account with the Error Reporting Writer role and
///   nothing else (`applicationDefaultCredentials` on Google Cloud).
///
/// Answers 204 when Error Reporting took the event, 400 when the event is not acceptable, 403 for a service
/// that is not allowed, and 503 with `Retry-After` when Error Reporting or the token was unavailable.
Handler errorReportingRelay({
  required String projectId,
  required Set<String> services,
  required Future<String> Function() accessToken,
  RegExp? versionPattern,
  http.Client? client,
  DateTime Function()? clock,
  void Function(String message)? log,
}) {
  final http.Client http_ = client ?? http.Client();
  final RegExp version = versionPattern ?? RegExp(r'^[0-9A-Za-z.+_-]{1,32}$');
  final DateTime Function() now = clock ?? DateTime.now;
  final void Function(String) note = log ?? (_) {};
  final Uri endpoint = Uri.https(
    'clouderrorreporting.googleapis.com',
    '/v1beta1/projects/$projectId/events:report',
  );

  return (Request request) async {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bodyOf(request)));
    } on FormatException {
      return Response(400);
    }
    if (json is! Map<String, Object?>) {
      return Response(400);
    }
    final Object? context = json['serviceContext'];
    final Object? service = context is Map<String, Object?>
        ? context['service']
        : null;
    final Object? serviceVersion = context is Map<String, Object?>
        ? context['version']
        : null;
    if (service is! String || !services.contains(service)) {
      note('refused: service not allowed');
      return Response(403);
    }
    if (serviceVersion != null &&
        (serviceVersion is! String || !version.hasMatch(serviceVersion))) {
      return Response(400);
    }
    final Object? message = json['message'];
    if (message is! String || message.isEmpty) {
      return Response(400);
    }

    final Map<String, Object?> event = <String, Object?>{
      'serviceContext': <String, Object?>{
        'service': service,
        'version': ?serviceVersion,
      },
      'message': message.length <= maxMessageLength
          ? message
          : message.substring(0, maxMessageLength),
    };
    final String? eventTime = _eventTime(json['eventTime'], now());
    if (eventTime != null) {
      event['eventTime'] = eventTime;
    }
    final Map<String, Object?> errorContext = <String, Object?>{};
    final String? uid = callerOf(request).uid;
    if (uid != null) {
      errorContext['user'] = uid;
    }
    final Object? original = json['context'];
    if (original is Map<String, Object?>) {
      final Map<String, Object?>? location = _location(
        original['reportLocation'],
      );
      if (location != null) {
        errorContext['reportLocation'] = location;
      }
      final Map<String, Object?>? httpRequest = _httpRequest(
        original['httpRequest'],
      );
      if (httpRequest != null) {
        errorContext['httpRequest'] = httpRequest;
      }
    }
    if (errorContext.isNotEmpty) {
      event['context'] = errorContext;
    }

    final String token;
    try {
      token = await accessToken();
    } on Object catch (e) {
      note('no access token (${e.runtimeType})');
      return Response(503, headers: <String, String>{'retry-after': '30'});
    }
    final http.Response answer;
    try {
      answer = await http_
          .post(
            endpoint,
            headers: <String, String>{
              'authorization': 'Bearer $token',
              'content-type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(event),
          )
          .timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      note('Error Reporting unreachable (${e.runtimeType})');
      return Response(503, headers: <String, String>{'retry-after': '30'});
    }
    if (answer.statusCode >= 200 && answer.statusCode < 300) {
      return Response(204);
    }
    if (answer.statusCode == 429 || answer.statusCode >= 500) {
      return Response(503, headers: <String, String>{'retry-after': '60'});
    }
    // 401 or 403 here means the relay's own credential is wrong: a problem of the server, not of the event.
    if (answer.statusCode == 401 || answer.statusCode == 403) {
      note(
        'Error Reporting refused the relay\'s credential (HTTP ${answer.statusCode})',
      );
      return Response(503, headers: <String, String>{'retry-after': '300'});
    }
    note('Error Reporting refused an event (HTTP ${answer.statusCode})');
    return Response(400);
  };
}

String? _eventTime(Object? value, DateTime now) {
  if (value is! String) {
    return null;
  }
  final DateTime? time = DateTime.tryParse(value);
  if (time == null ||
      time.isBefore(now.subtract(const Duration(days: 30))) ||
      time.isAfter(now.add(const Duration(hours: 1)))) {
    return null;
  }
  return time.toUtc().toIso8601String();
}

String? _text(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return value.length <= maxFieldLength
      ? value
      : value.substring(0, maxFieldLength);
}

Map<String, Object?>? _location(Object? value) {
  if (value is! Map<String, Object?>) {
    return null;
  }
  final String? file = _text(value['filePath']);
  final String? function = _text(value['functionName']);
  final Object? line = value['lineNumber'];
  if (file == null || function == null) {
    return null;
  }
  return <String, Object?>{
    'filePath': file,
    'functionName': function,
    'lineNumber': line is int && line >= 0 && line < 1 << 31 ? line : 0,
  };
}

Map<String, Object?>? _httpRequest(Object? value) {
  if (value is! Map<String, Object?>) {
    return null;
  }
  final Object? status = value['responseStatusCode'];
  final Map<String, Object?> out = <String, Object?>{
    'method': ?_text(value['method']),
    'url': ?_text(value['url']),
    'userAgent': ?_text(value['userAgent']),
    'referrer': ?_text(value['referrer']),
    if (status is int && status >= 100 && status <= 599)
      'responseStatusCode': status,
  };
  // remoteIp is left out: the relay sees the client's address itself, and a caller could put anything there.
  return out.isEmpty ? null : out;
}
