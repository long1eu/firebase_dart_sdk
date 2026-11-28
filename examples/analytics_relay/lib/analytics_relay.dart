/// The handler of the relay: it takes a Measurement Protocol body that `relayGuard` let through, checks its
/// shape, and forwards it to Google Analytics with the API secret, which only the relay holds.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart';

/// The largest body the client sends, in bytes (`AnalyticsLimits.maxBodyBytes`: "less than 130kB").
const int clientMaxBodyBytes = 130000;

/// The `maxBodyBytes` to give `relayGuard`: room for the largest body the client sends.
const int guardMaxBodyBytes = 128 * 1024;

/// The most events in one request (Measurement Protocol limit; the client never sends more).
const int maxEventsPerRequest = 25;

/// The longest `client_id` forwarded, in characters. The client's own ids are about 21.
const int maxClientIdLength = 256;

/// Where the relay forwards: Google's global collection endpoint, or the one that collects in the EU.
enum CollectionRegion {
  /// `www.google-analytics.com`.
  global('www.google-analytics.com'),

  /// `region1.google-analytics.com`, for data collected in the EU.
  eu('region1.google-analytics.com');

  const CollectionRegion(this.host);

  /// The host of the collection endpoint.
  final String host;
}

final RegExp _measurementIdPattern = RegExp(r'^G-[A-Z0-9]{4,20}$');

/// Body fields that name a stream or carry a credential: only the relay's configuration may set them.
const Set<String> _forbiddenFields = <String>{'api_secret', 'measurement_id'};

/// A handler that forwards each Measurement Protocol body to the GA4 web stream [measurementId] with
/// [apiSecret], at [region].
///
/// * The upstream URL is built only from this configuration: `/mp/collect` at the host of [region], with
///   [measurementId] and [apiSecret] as `measurement_id` and `api_secret`. The caller's query may hold nothing but `measurement_id`, which the client always adds,
///   and then it must equal [measurementId]. An `api_secret` there is refused with 400; anything else with
///   403, which the client keeps until the app's relay URL and this configuration agree.
/// * With [allowedAppIds], the caller's verified App Check app id must be one of them; otherwise 403, which
///   the client keeps, so that a typo in the list does not drop a real app's events.
/// * The body must be a JSON object with a non-empty string `client_id` (at most [maxClientIdLength]
///   characters) and an `events` list of 1 to [maxEventsPerRequest] objects, each with a non-empty string
///   `name`. A body with `api_secret` or `measurement_id` is refused. Anything else in the body is the
///   client's and is passed on as it is; the relay never rewrites `client_id`. What is forwarded is the
///   decoded body encoded again, so that duplicate keys cannot show Google something the relay did not check.
/// * Only `Content-Type` goes upstream: none of the caller's headers (tokens, the app id, the address).
///
/// Google Analytics gets [timeout] (10 seconds), with no redirect followed and no retry: the client retries.
/// Its answer becomes 204 (2xx: delivered), 400 (400, 413 or 422: the body itself was refused, and the
/// client drops the batch) or 503 with `Retry-After` (anything else: 5xx, 429, a redirect, another 4xx such
/// as the 401 or 404 of a wrong secret or path, a network error or the timeout; the client keeps the events
/// and tries again). A refusal of the body by the relay itself is 400 or 413, which the client drops. Every answer
/// carries `Connection: close`. No answer has a body, and
/// [log] never gets the secret or the upstream URL: only statuses and error types.
Handler analyticsRelay({
  required String measurementId,
  required String apiSecret,
  CollectionRegion region = CollectionRegion.global,
  Set<String>? allowedAppIds,
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
  void Function(String message)? log,
}) {
  if (!_measurementIdPattern.hasMatch(measurementId)) {
    // Never quote the value: with the two settings swapped, it would be the secret.
    throw ArgumentError(
      'Not the Measurement ID of a GA4 web data stream (G- followed by letters and digits).',
      'measurementId',
    );
  }
  if (apiSecret.isEmpty || apiSecret.contains(RegExp(r'[\s\x00-\x1f\x7f]'))) {
    // Never quote the value: it is the secret.
    throw ArgumentError(
      'The API secret must be a non-empty string without spaces.',
      'apiSecret',
    );
  }
  final http.Client httpClient = client ?? http.Client();
  final void Function(String) note = log ?? (_) {};
  // Holds the secret: never logged, never part of an answer.
  final Uri endpoint = Uri.https(region.host, '/mp/collect', <String, String>{
    'measurement_id': measurementId,
    'api_secret': apiSecret,
  });

  Future<Response> handle(Request request) async {
    for (final MapEntry<String, List<String>> entry
        in request.url.queryParametersAll.entries) {
      if (entry.key == 'api_secret') {
        // No client of this relay sends one: refused for good. Never logged: it could be a real secret.
        note('refused: api_secret in the query');
        return Response(400);
      }
      if (entry.key != 'measurement_id' ||
          entry.value.length != 1 ||
          entry.value.single != measurementId) {
        // A mismatch between the app's relay URL and this relay's configuration: 403, which the client keeps,
        // so the events survive until the configuration is fixed. The name only: a value could be a secret.
        note('refused: query parameter ${_printable(entry.key)}');
        return Response(403);
      }
    }
    if (allowedAppIds != null) {
      final String? appId = callerOf(request).appId;
      if (appId == null || !allowedAppIds.contains(appId)) {
        // 403, which the client keeps: a typo in ALLOWED_APP_IDS must not drop the events of a real app. The
        // rate limits bound what a refused app can send meanwhile.
        note('refused: app ${appId ?? '(none)'} is not allowed');
        return Response(403);
      }
    }

    final List<int> body = bodyOf(request);
    if (body.length > clientMaxBodyBytes) {
      note('refused: a body of ${body.length} bytes');
      return Response(413);
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException {
      note('refused: not JSON');
      return Response(400);
    }
    final String? problem = _problem(json);
    if (problem != null) {
      note('refused: $problem');
      return Response(400);
    }

    // Encoded before anything goes upstream: 1e999 decodes to infinity, which JSON cannot carry, and very deep
    // nesting overflows the stack. Both are the body's fault, not an outage.
    final List<int> forwarded;
    try {
      forwarded = utf8.encode(jsonEncode(json));
    } on Object catch (e) {
      note('refused: the body cannot be encoded again (${e.runtimeType})');
      return Response(400);
    }

    final int status;
    final Completer<void> abort = Completer<void>();
    try {
      status = await _forward(httpClient, endpoint, forwarded, abort.future)
          .timeout(
            timeout,
            onTimeout: () {
              // Close the connection too: nothing waits for its answer any more.
              abort.complete();
              throw TimeoutException(null);
            },
          );
    } on TimeoutException {
      note('Google Analytics did not answer within ${timeout.inSeconds} s');
      return _unavailable;
    } on Object catch (e) {
      // Only the type: the message of a ClientException quotes the URL, which holds the secret.
      note('Google Analytics unreachable (${e.runtimeType})');
      return _unavailable;
    }
    if (status >= 200 && status < 300) {
      return Response(204);
    }
    note('Google Analytics answered HTTP $status');
    if (status == 400 || status == 413 || status == 422) {
      // The body itself was refused: sending it again cannot help.
      return Response(400);
    }
    // 5xx and 429 are an outage or a quota. A redirect, 401, 403, 404 and the other 4xx point at the relay
    // (a wrong secret, stream or path), not at the events: keep them until the relay is fixed.
    return _unavailable;
  }

  // Every answer closes the connection: a proxy that reused it could send the next request on a connection
  // near the deadline of serveGuarded, which then cuts it after Google took the events, and the client would
  // send them twice.
  return (Request request) async => (await handle(
    request,
  )).change(headers: <String, String>{'connection': 'close'});
}

Response get _unavailable =>
    Response(503, headers: <String, String>{'retry-after': '60'});

/// Sends [body] once and returns the status, without following a redirect. [abort] cancels the request.
Future<int> _forward(
  http.Client client,
  Uri endpoint,
  List<int> body,
  Future<void> abort,
) async {
  final http.Request request =
      http.AbortableRequest('POST', endpoint, abortTrigger: abort)
        ..followRedirects = false
        ..headers['content-type'] = 'application/json'
        ..bodyBytes = body;
  final http.StreamedResponse response = await client.send(request);
  int read = 0;
  await for (final List<int> chunk in response.stream) {
    read += chunk.length;
    if (read >= 16 * 1024) {
      break;
    }
  }
  return response.statusCode;
}

/// What is wrong with [json] as a Measurement Protocol body, or null.
String? _problem(Object? json) {
  if (json is! Map<String, Object?>) {
    return 'the body is not a JSON object';
  }
  for (final String field in _forbiddenFields) {
    if (json.containsKey(field)) {
      return 'the body has $field';
    }
  }
  final Object? clientId = json['client_id'];
  if (clientId is! String ||
      clientId.isEmpty ||
      clientId.length > maxClientIdLength) {
    return 'no valid client_id';
  }
  final Object? events = json['events'];
  if (events is! List<Object?> || events.isEmpty) {
    return 'no events';
  }
  if (events.length > maxEventsPerRequest) {
    return '${events.length} events, more than $maxEventsPerRequest';
  }
  for (final Object? event in events) {
    if (event is! Map<String, Object?>) {
      return 'an event is not an object';
    }
    final Object? name = event['name'];
    if (name is! String || name.isEmpty) {
      return 'an event has no name';
    }
  }
  return null;
}

/// [text] without control characters, cut to 40 characters, for the log.
String _printable(String text) {
  final String clean = text.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '?');
  return clean.length <= 40 ? clean : '${clean.substring(0, 40)}…';
}
