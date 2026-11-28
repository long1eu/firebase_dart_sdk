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

  /// Sends [body] once. Never throws.
  @internal
  Future<SendResult> send(
    http.Client client,
    FirebaseApp app,
    Map<String, Object?> body,
  );
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

  /// The `Retry-After` of the answer, capped at an hour.
  final Duration? after;
}

/// The server refused the event: sending it again would fail the same way.
@internal
final class Dropped extends SendResult {
  /// A refusal with its [status] and the start of the answer ([body]).
  const Dropped(this.status, this.body);

  /// The HTTP status.
  final int status;

  /// At most [maxResponseBytes] of the answer.
  final String body;
}

/// The most of an answer that is read.
@internal
const int maxResponseBytes = 64 * 1024;

/// How long one request may take.
@internal
const Duration requestTimeout = Duration(seconds: 30);

/// Whether tokens may travel to [url]: over https, or to a loopback host.
@internal
bool mayCarryTokens(Uri url) {
  if (url.scheme == 'https') {
    return true;
  }
  final String host = url.host.toLowerCase();
  return url.scheme == 'http' &&
      (host == 'localhost' ||
          host == '::1' ||
          RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host));
}

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
    Map<String, Object?> body,
  ) async {
    final Map<String, String> headers = <String, String>{};
    final String? appCheck = await _appCheckToken(app);
    if (appCheck != null) {
      headers['x-firebase-appcheck'] = appCheck;
    }
    final String? idToken = await _idToken(app);
    if (idToken != null) {
      headers['authorization'] = 'Bearer $idToken';
    }
    final _Answer answer = await _post(client, url, headers, body);
    return answer.result;
  }

  static Future<String?> _appCheckToken(FirebaseApp app) async {
    final AppCheckTokenProvider? provider = app.appCheckProvider;
    if (provider == null) {
      return null;
    }
    try {
      final AppCheckTokenResult result = await provider.getToken(
        forceRefresh: false,
      );
      return result.token.isEmpty ? null : result.token;
    } on Object {
      // As in the other packages: the request goes out without the header and the relay decides.
      return null;
    }
  }

  static Future<String?> _idToken(FirebaseApp app) async {
    final AuthTokenProvider provider = app.authProvider;
    if (identical(provider, app)) {
      // The app is its own provider when none was set: nobody can be signed in.
      return null;
    }
    try {
      final GetTokenResult result = await provider.getAccessToken(
        forceRefresh: false,
      );
      return result.token.isEmpty ? null : result.token;
    } on Object {
      // Nobody signed in, or the provider failed: the error is reported without a user.
      return null;
    }
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
    Map<String, Object?> body,
  ) async {
    final String projectId = app.options.projectId ?? '';
    final Uri url = endpoint(projectId);
    final AuthTokenProvider? provider = credentials;
    if (provider == null) {
      return (await _post(client, url, const <String, String>{}, body)).result;
    }
    for (bool refresh = false; ; refresh = true) {
      final String token;
      try {
        token = (await provider.getAccessToken(forceRefresh: refresh)).token;
      } on Object catch (error) {
        // The provider's message may quote what it was given; only the type.
        return RetryLater('the credentials failed (${error.runtimeType})');
      }
      if (token.isEmpty) {
        return const RetryLater('the credentials gave an empty token');
      }
      final _Answer answer = await _post(client, url, <String, String>{
        'authorization': 'Bearer $token',
      }, body);
      if (answer.status == 401 && !refresh) {
        continue;
      }
      return answer.result;
    }
  }
}

final class _Answer {
  _Answer(this.result, [this.status]);

  final SendResult result;
  final int? status;
}

Future<_Answer> _post(
  http.Client client,
  Uri url,
  Map<String, String> headers,
  Map<String, Object?> body,
) async {
  final http.Request request = http.Request('POST', url)
    ..followRedirects = false
    ..headers.addAll(headers)
    ..headers['content-type'] = 'application/json; charset=utf-8'
    ..bodyBytes = utf8.encode(jsonEncode(body));
  final http.StreamedResponse response;
  try {
    response = await client.send(request).timeout(requestTimeout);
  } on TimeoutException {
    return _Answer(const RetryLater('no answer in time'));
  } on Object catch (error) {
    // The message of a client error can quote the URL, which may hold the key.
    return _Answer(RetryLater('the request failed (${error.runtimeType})'));
  }
  final String text = await _read(response);
  final int status = response.statusCode;
  if (status >= 200 && status < 300) {
    return _Answer(const Delivered(), status);
  }
  if (status == 408 || status == 429 || status >= 500) {
    return _Answer(
      RetryLater(
        'HTTP $status',
        after: _retryAfter(response.headers['retry-after']),
      ),
      status,
    );
  }
  return _Answer(Dropped(status, text), status);
}

Future<String> _read(http.StreamedResponse response) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  final Completer<void> done = Completer<void>();
  late final StreamSubscription<List<int>> subscription;
  subscription = response.stream.listen(
    (List<int> chunk) {
      final int room = maxResponseBytes - builder.length;
      if (chunk.length >= room) {
        builder.add(chunk.sublist(0, room));
        subscription.cancel();
        if (!done.isCompleted) {
          done.complete();
        }
        return;
      }
      builder.add(chunk);
    },
    onDone: () {
      if (!done.isCompleted) {
        done.complete();
      }
    },
    onError: (Object _) {
      // Keep what arrived: the status is what matters.
      if (!done.isCompleted) {
        done.complete();
      }
    },
    cancelOnError: true,
  );
  try {
    await done.future.timeout(requestTimeout);
  } on TimeoutException {
    await subscription.cancel();
  }
  return utf8.decode(builder.takeBytes(), allowMalformed: true);
}

Duration? _retryAfter(String? value) {
  final int? seconds = value == null ? null : int.tryParse(value.trim());
  if (seconds == null || seconds < 0) {
    return null;
  }
  return Duration(seconds: seconds > 3600 ? 3600 : seconds);
}
