import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// How an `ErrorReporter` delivers events.
///
/// * [ErrorReportingTransport.relay]: to a server you run, which checks the request and forwards it to Error
///   Reporting with its own service account. The recommended transport for apps in users' hands, because no
///   credential of the project ships in the app.
/// * [ErrorReportingTransport.direct]: straight to `projects.events.report`, with OAuth credentials (a
///   service account, Application Default Credentials) or an API key. For servers, jobs and internal tools.
sealed class ErrorReportingTransport {
  const ErrorReportingTransport._();

  /// Posts each event, as the JSON of a `ReportedErrorEvent`, to [url].
  ///
  /// The request carries the App Check token of `app.appCheckProvider` in `X-Firebase-AppCheck` and, when a
  /// user is signed in, the ID token of `app.authProvider` as `Authorization: Bearer`. [url] must be https,
  /// or http to a loopback host for development; anything else throws an [ArgumentError], because the events
  /// and tokens would travel in clear text.
  ///
  /// The relay must check the tokens, cap the size, limit the rate per App Check token or user, set
  /// `serviceContext` from a list it trusts rather than from the body, and forward the event to
  /// `events:report` with a service account that has the Error Reporting Writer role and nothing else.
  factory ErrorReportingTransport.relay(Uri url) = RelayTransport;

  /// Calls `https://clouderrorreporting.googleapis.com/v1beta1/projects/<project id>/events:report`, the
  /// project being the `projectId` of the app's options.
  ///
  /// Give exactly one of:
  ///
  /// * [credentials]: a provider of OAuth access tokens with the scope
  ///   `https://www.googleapis.com/auth/cloud-platform`, for an account with the Error Reporting Writer role,
  ///   such as `OAuthTokenProvider.serviceAccount(key, scopes: [...])` of `firebase_auth_providers_dart`. On
  ///   HTTP 401 the reporter asks it for a new token once.
  /// * [apiKey]: an API key, sent as the `key` query parameter. Restrict it to the Error Reporting API.
  ///   Anyone who extracts it from a program can post errors into the project, so use it only for tools you
  ///   run yourself.
  ///
  /// Never put a service account key in an app.
  factory ErrorReportingTransport.direct({
    AuthTokenProvider? credentials,
    String? apiKey,
  }) {
    if ((credentials == null) == (apiKey == null)) {
      throw ArgumentError(
        'Give exactly one of credentials and apiKey to ErrorReportingTransport.direct.',
      );
    }
    if (apiKey != null &&
        (apiKey.isEmpty || apiKey.contains(RegExp(r'[^A-Za-z0-9_\-]')))) {
      // The key is not quoted: it is a credential.
      throw ArgumentError(
        'The API key is empty or has characters an API key does not have.',
      );
    }
    return DirectTransport(credentials: credentials, apiKey: apiKey);
  }

  /// Sends [body] once. Never throws. [proceed] is asked right before the request goes out (after the tokens
  /// were fetched); when it answers false nothing is sent and the result is [Cancelled].
  @internal
  Future<SendResult> send(
    http.Client client,
    FirebaseApp app,
    Map<String, Object?> body, {
    bool Function()? proceed,
  });
}

/// The outcome of one attempt.
@internal
sealed class SendResult {
  const SendResult();
}

/// The server took the event.
@internal
final class Delivered extends SendResult {
  /// The result of a 2xx answer.
  const Delivered();
}

/// The attempt failed for a reason that may pass: send again later.
@internal
final class RetryLater extends SendResult {
  /// A failure with the wait the server asked for ([after]), if any, and a short [reason] for the log.
  const RetryLater(this.reason, {this.after});

  /// What happened, without tokens or keys.
  final String reason;

  /// The `Retry-After` of the answer, or the pause the transport asks for, capped at an hour.
  final Duration? after;
}

/// The server refused the event: sending it again would fail the same way.
@internal
final class Dropped extends SendResult {
  /// A refusal with its [status] (0 when the event never left) and the start of the answer ([body]).
  const Dropped(this.status, this.body);

  /// The HTTP status, or 0.
  final int status;

  /// At most [maxResponseBytes] of the answer, with the credentials of the request removed.
  final String body;
}

/// Nothing was sent: the reporter no longer wanted the event when the request was about to go out.
@internal
final class Cancelled extends SendResult {
  /// The result when `proceed` answered false.
  const Cancelled();
}

/// The most of an answer that is read.
@internal
const int maxResponseBytes = 64 * 1024;

/// How long one request may take, from sending to the end of the answer.
@internal
const Duration requestTimeout = Duration(seconds: 30);

/// How long a token provider may take.
@internal
const Duration tokenTimeout = Duration(seconds: 10);

/// How long the queue pauses when the relay refuses the tokens (401 or 403).
@internal
const Duration relayRefusalPause = Duration(minutes: 5);

/// Whether tokens may travel to [url]: over https, or to a loopback host.
@internal
bool mayCarryTokens(Uri url) {
  if (url.scheme == 'https') {
    return true;
  }
  if (url.scheme != 'http') {
    return false;
  }
  final String host = url.host.toLowerCase();
  if (host == 'localhost' || host == '::1') {
    return true;
  }
  final RegExpMatch? match = RegExp(
    r'^127\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
  ).firstMatch(host);
  return match != null &&
      <String?>[
        match.group(1),
        match.group(2),
        match.group(3),
      ].every((String? octet) => int.parse(octet!) <= 255);
}

/// Whether [value] may go into a header: printable ASCII without spaces (tokens and keys have none).
bool _isHeaderSafe(String value) =>
    value.isNotEmpty && RegExp(r'^[\x21-\x7e]+$').hasMatch(value);

/// A token from a provider: the token, null when there is none to send, or a [RetryLater] when the provider
/// failed.
typedef _Token = ({String? token, RetryLater? failure});

/// The relay transport.
@internal
final class RelayTransport extends ErrorReportingTransport {
  /// A relay at [url].
  RelayTransport(this.url) : super._() {
    if (!mayCarryTokens(url) || url.host.isEmpty) {
      throw ArgumentError(
        'The relay URL must be https, or http to a loopback host; it was ${url.scheme}.',
      );
    }
  }

  /// Where events go.
  final Uri url;

  @override
  Future<SendResult> send(
    http.Client client,
    FirebaseApp app,
    Map<String, Object?> body, {
    bool Function()? proceed,
  }) async {
    final Map<String, String> headers = <String, String>{};
    final _Token appCheck = await _appCheckToken(app);
    if (appCheck.failure != null) {
      return appCheck.failure!;
    }
    if (appCheck.token != null) {
      headers['x-firebase-appcheck'] = appCheck.token!;
    }
    final _Token idToken = await _idToken(app);
    if (idToken.failure != null) {
      return idToken.failure!;
    }
    if (idToken.token != null) {
      headers['authorization'] = 'Bearer ${idToken.token}';
    }
    if (proceed != null && !proceed()) {
      return const Cancelled();
    }
    final SendResult result = await _post(client, url, headers, body);
    if (result is Dropped && (result.status == 401 || result.status == 403)) {
      // The relay refused the tokens: that may pass (a provider that recovers, a relay being fixed), so the
      // queue pauses instead of dropping every event in turn.
      return RetryLater(
        'the relay refused the request (HTTP ${result.status})',
        after: relayRefusalPause,
      );
    }
    return result;
  }

  static Future<_Token> _appCheckToken(FirebaseApp app) async {
    final AppCheckTokenProvider? provider = app.appCheckProvider;
    if (provider == null) {
      return (token: null, failure: null);
    }
    try {
      final AppCheckTokenResult result = await provider
          .getToken(forceRefresh: false)
          .timeout(tokenTimeout);
      return _checked(result.token, 'App Check');
    } on Object catch (error) {
      // A configured App Check that fails: the relay would refuse the request, so try again later.
      return (
        token: null,
        failure: RetryLater(
          'the App Check token failed (${error.runtimeType})',
        ),
      );
    }
  }

  static Future<_Token> _idToken(FirebaseApp app) async {
    final AuthTokenProvider provider = app.authProvider;
    if (identical(provider, app)) {
      // The app is its own provider when none was set: nobody can be signed in.
      return (token: null, failure: null);
    }
    try {
      final GetTokenResult result = await provider
          .getAccessToken(forceRefresh: false)
          .timeout(tokenTimeout);
      return _checked(result.token, 'ID');
    } on FirebaseNoSignedInUserException {
      return (token: null, failure: null);
    } on FirebaseApiNotAvailableException {
      return (token: null, failure: null);
    } on Object catch (error) {
      return (
        token: null,
        failure: RetryLater('the ID token failed (${error.runtimeType})'),
      );
    }
  }

  static _Token _checked(String token, String kind) {
    if (token.isEmpty) {
      return (token: null, failure: null);
    }
    if (!_isHeaderSafe(token)) {
      return (
        token: null,
        failure: RetryLater(
          'the $kind token has characters a header cannot hold',
        ),
      );
    }
    return (token: token, failure: null);
  }
}

/// The direct transport.
@internal
final class DirectTransport extends ErrorReportingTransport {
  /// A transport with [credentials] or [apiKey].
  const DirectTransport({this.credentials, this.apiKey}) : super._();

  /// The OAuth token provider, or null with an API key.
  final AuthTokenProvider? credentials;

  /// The API key, or null with credentials.
  final String? apiKey;

  /// The endpoint of [projectId].
  Uri endpoint(String projectId) => Uri.https(
    'clouderrorreporting.googleapis.com',
    '/v1beta1/projects/$projectId/events:report',
    apiKey == null ? null : <String, String>{'key': apiKey!},
  );

  @override
  Future<SendResult> send(
    http.Client client,
    FirebaseApp app,
    Map<String, Object?> body, {
    bool Function()? proceed,
  }) async {
    final String projectId = app.options.projectId ?? '';
    final Uri url = endpoint(projectId);
    final AuthTokenProvider? provider = credentials;
    if (provider == null) {
      if (proceed != null && !proceed()) {
        return const Cancelled();
      }
      return _post(
        client,
        url,
        const <String, String>{},
        body,
        secrets: <String>[apiKey!],
      );
    }
    for (bool refresh = false; ; refresh = true) {
      final String token;
      try {
        token =
            (await provider
                    .getAccessToken(forceRefresh: refresh)
                    .timeout(tokenTimeout))
                .token;
      } on Object catch (error) {
        // The provider's message may quote what it was given; only the type.
        return RetryLater('the credentials failed (${error.runtimeType})');
      }
      if (!_isHeaderSafe(token)) {
        return const RetryLater(
          'the credentials gave an empty token, or one a header cannot hold',
        );
      }
      if (proceed != null && !proceed()) {
        return const Cancelled();
      }
      final SendResult result = await _post(client, url, <String, String>{
        'authorization': 'Bearer $token',
      }, body);
      if (result is Dropped && result.status == 401 && !refresh) {
        continue;
      }
      return result;
    }
  }
}

/// Posts [body] to [url] with [headers], within [requestTimeout] from the start to the end of the answer. The
/// request is aborted at the deadline. The values of [headers] and [secrets] are removed from the body of a
/// refusal before it is returned.
Future<SendResult> _post(
  http.Client client,
  Uri url,
  Map<String, String> headers,
  Map<String, Object?> body, {
  List<String> secrets = const <String>[],
}) async {
  final List<int> bytes;
  try {
    bytes = utf8.encode(jsonEncode(body));
  } on Object catch (error) {
    // A value JSON cannot hold (a non-finite number from a store, say): it can never be sent.
    return Dropped(0, 'the event could not be encoded (${error.runtimeType})');
  }
  final Completer<void> abort = Completer<void>();
  final Timer deadline = Timer(requestTimeout, () {
    if (!abort.isCompleted) {
      abort.complete();
    }
  });
  try {
    final http.AbortableRequest request =
        http.AbortableRequest('POST', url, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll(headers)
          ..headers['content-type'] = 'application/json; charset=utf-8'
          ..bodyBytes = bytes;
    final http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(requestTimeout);
    } on TimeoutException {
      return const RetryLater('no answer in time');
    } on Object catch (error) {
      // The message of a client error can quote the URL, which may hold the key.
      return RetryLater('the request failed (${error.runtimeType})');
    }
    final String text = await _read(response, abort.future);
    final int status = response.statusCode;
    if (status >= 200 && status < 300) {
      return const Delivered();
    }
    if (status == 408 || status == 429 || status >= 500) {
      return RetryLater(
        'HTTP $status',
        after: _retryAfter(response.headers['retry-after']),
      );
    }
    return Dropped(
      status,
      _redact(text, <String>[...headers.values, ...secrets]),
    );
  } finally {
    deadline.cancel();
  }
}

String _redact(String text, List<String> secrets) {
  String out = text;
  for (final String secret in secrets) {
    for (final String value in <String>{
      secret,
      if (secret.startsWith('Bearer ')) secret.substring(7),
    }) {
      if (value.length >= 8) {
        out = out.replaceAll(value, '<redacted>');
      }
    }
  }
  return out;
}

Future<String> _read(http.StreamedResponse response, Future<void> abort) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  final Completer<void> done = Completer<void>();
  void finish() {
    if (!done.isCompleted) {
      done.complete();
    }
  }

  late final StreamSubscription<List<int>> subscription;
  subscription = response.stream.listen(
    (List<int> chunk) {
      final int room = maxResponseBytes - builder.length;
      if (chunk.length >= room) {
        builder.add(chunk.sublist(0, room));
        subscription.cancel();
        finish();
        return;
      }
      builder.add(chunk);
    },
    onDone: finish,
    // Keep what arrived: the status is what matters.
    onError: (Object _) => finish(),
    cancelOnError: true,
  );
  unawaited(
    abort.then((_) {
      subscription.cancel();
      finish();
    }),
  );
  await done.future;
  return utf8.decode(builder.takeBytes(), allowMalformed: true);
}

Duration? _retryAfter(String? value) {
  final int? seconds = value == null ? null : int.tryParse(value.trim());
  if (seconds == null || seconds < 0) {
    return null;
  }
  return Duration(seconds: seconds > 3600 ? 3600 : seconds);
}
