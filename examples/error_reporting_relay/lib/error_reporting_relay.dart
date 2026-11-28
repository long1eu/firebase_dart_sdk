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
///   them, so a caller cannot fill the console with services of its own. With [servicesByApp], the service must
///   also be one of those of the caller's verified app id (the web app cannot report as the desktop app). The
///   version must match [versionPattern] (by default a release such as `1.4.0`, at most 32 characters).
/// * The event is rebuilt from `eventTime` (dropped unless it is an RFC 3339 time with a zone within the last
///   30 days or the next hour), `message` (control characters other than line breaks and tabs removed, cut at
///   [maxMessageLength]), `serviceContext`, `context.reportLocation` and `context.httpRequest` (control
///   characters removed, fields cut at [maxFieldLength], `remoteIp` left out). Anything else is left out.
/// * `context.user` is the uid of the verified ID token, never what the caller wrote: without a signed-in user
///   there is no user.
/// * [accessToken] gives an OAuth access token of a service account with the Error Reporting Writer role and
///   nothing else (`applicationDefaultCredentials` on Google Cloud). After a 401 from Error Reporting it is
///   called once more with `forceRefresh: true`.
///
/// Answers 204 when Error Reporting took the event; 400 when the event is malformed or Error Reporting refused
/// it with 400; 422 for a service that is not allowed; 503 with `Retry-After` for anything that is the relay's
/// or Error Reporting's problem (no token, a refused credential, a wrong project, an outage). The client drops
/// events on 400 and 422 and keeps them on 503. Error Reporting gets 10 seconds, so the relay answers before
/// the client's own 30-second deadline.
Handler errorReportingRelay({
  required String projectId,
  required Set<String> services,
  required Future<String> Function({bool forceRefresh}) accessToken,
  Map<String, Set<String>>? servicesByApp,
  RegExp? versionPattern,
  http.Client? client,
  DateTime Function()? clock,
  void Function(String message)? log,
}) {
  final http.Client httpClient = client ?? http.Client();
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
      return Response(422);
    }
    if (servicesByApp != null) {
      final String? appId = callerOf(request).appId;
      if (appId == null ||
          !(servicesByApp[appId]?.contains(service) ?? false)) {
        note('refused: service $service not allowed for app $appId');
        return Response(422);
      }
    }
    if (serviceVersion != null &&
        (serviceVersion is! String || !version.hasMatch(serviceVersion))) {
      return Response(400);
    }
    final Object? rawMessage = json['message'];
    if (rawMessage is! String) {
      return Response(400);
    }
    final String message = _cut(
      _clean(rawMessage, keepLines: true),
      maxMessageLength,
    );
    if (message.trim().isEmpty) {
      return Response(400);
    }

    final Map<String, Object?> event = <String, Object?>{
      'serviceContext': <String, Object?>{
        'service': service,
        'version': ?serviceVersion,
      },
      'message': message,
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

    late http.Response answer;
    for (bool refresh = false; ; refresh = true) {
      final String token;
      try {
        token = await accessToken(forceRefresh: refresh);
      } on Object catch (e) {
        note('no access token (${e.runtimeType})');
        return Response(503, headers: <String, String>{'retry-after': '30'});
      }
      try {
        answer = await httpClient
            .post(
              endpoint,
              headers: <String, String>{
                'authorization': 'Bearer $token',
                'content-type': 'application/json; charset=utf-8',
              },
              body: jsonEncode(event),
            )
            .timeout(const Duration(seconds: 10));
      } on Object catch (e) {
        note('Error Reporting unreachable (${e.runtimeType})');
        return Response(503, headers: <String, String>{'retry-after': '30'});
      }
      if (answer.statusCode == 401 && !refresh) {
        continue;
      }
      break;
    }
    final int status = answer.statusCode;
    if (status >= 200 && status < 300) {
      return Response(204);
    }
    if (status == 400) {
      note('Error Reporting refused an event (HTTP 400)');
      return Response(400);
    }
    // Anything else is not the event's fault: a refused credential (401, 403), a wrong project (404), an
    // outage (429, 5xx). The client keeps the event and tries again.
    note('Error Reporting answered HTTP $status');
    return Response(
      503,
      headers: <String, String>{
        'retry-after': status == 401 || status == 403 || status == 404
            ? '300'
            : '60',
      },
    );
  };
}

/// RFC 3339 with a zone: `2026-11-28T12:00:00Z` or `...+02:00`, optional fractions.
final RegExp _rfc3339 = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$',
);

String? _eventTime(Object? value, DateTime now) {
  if (value is! String) {
    return null;
  }
  final RegExpMatch? match = _rfc3339.firstMatch(value);
  if (match == null) {
    return null;
  }
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  final int hour = int.parse(match.group(4)!);
  final int minute = int.parse(match.group(5)!);
  final int second = int.parse(match.group(6)!);
  // DateTime.parse would roll 25:61 into the next day: refuse instead.
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
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
  if (value is! String) {
    return null;
  }
  final String text = _cut(_clean(value, keepLines: false), maxFieldLength);
  return text.trim().isEmpty ? null : text;
}

/// [text] without control characters (line breaks and tabs kept when [keepLines]).
String _clean(String text, {required bool keepLines}) => text.replaceAll(
  keepLines
      ? RegExp('[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]')
      : RegExp('[\\x00-\\x1f\\x7f]'),
  '',
);

/// [text] cut to [max] UTF-16 units without splitting a surrogate pair.
String _cut(String text, int max) {
  if (text.length <= max) {
    return text;
  }
  int end = max;
  final int unit = text.codeUnitAt(end - 1);
  if (unit >= 0xd800 && unit <= 0xdbff) {
    end--;
  }
  return text.substring(0, end);
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
