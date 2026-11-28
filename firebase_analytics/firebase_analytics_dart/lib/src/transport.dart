import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'client_identity.dart';

/// Where the Measurement Protocol is collected: Google's global endpoint, or the one that collects in the EU
/// (`region1.google-analytics.com`). It applies to [AnalyticsTransport.direct]; a relay chooses for itself.
enum AnalyticsRegion {
  /// `www.google-analytics.com`.
  global('www.google-analytics.com'),

  /// `region1.google-analytics.com`, for data collected in the EU.
  eu('region1.google-analytics.com');

  const AnalyticsRegion(this.host);

  /// The host of the collection endpoint.
  final String host;
}

/// How events reach Google Analytics.
///
/// Every Measurement Protocol request needs an API secret of the GA4 data stream, which Google says to keep
/// private. A program that runs on the user's machine cannot keep it: anyone can extract it from the binary
/// and send fake events into the property. So there are two transports:
///
/// - [AnalyticsTransport.relay] (recommended for apps): events go to a server you run, which checks the
///   request, adds the secret and forwards the body to Google.
/// - [AnalyticsTransport.direct]: events go to Google with the secret. Use it only where the secret stays
///   private: a server, or an internal tool whose users you trust.
sealed class AnalyticsTransport {
  const AnalyticsTransport._();

  /// Sends each request to your server at [endpoint], without an API secret.
  ///
  /// The request is a `POST` of the Measurement Protocol JSON body to [endpoint] with the query parameter
  /// `measurement_id` added. It carries the header `X-Firebase-GMPID` (the app id), the App Check token of
  /// `app.appCheckProvider` in `X-Firebase-AppCheck` when the app has one, and the ID token of the signed-in
  /// user of `app.authProvider` as `Authorization: Bearer <token>` when someone is signed in. The relay
  /// checks the tokens, adds `api_secret` and forwards the body unchanged to
  /// `https://www.google-analytics.com/mp/collect`. A 2xx answer means delivered, 429 and 5xx are retried,
  /// and any other answer drops the request.
  ///
  /// [endpoint] must be `https`, or `http` to a loopback host (`localhost`, `127.x.x.x`, `::1`) for local
  /// development; otherwise this throws an [ArgumentError]. Tokens never travel in clear text to anybody
  /// else.
  factory AnalyticsTransport.relay(Uri endpoint) = RelayTransport._;

  /// Sends each request straight to Google with [apiSecret], the Measurement Protocol API secret of the
  /// stream (Admin > Data streams > the stream > Measurement Protocol API secrets).
  ///
  /// The secret ends up in the program. Use this only on a server or in an internal tool; in an app shipped
  /// to users, use [AnalyticsTransport.relay]. The secret never appears in exceptions, warnings or
  /// [toString]. No auth or App Check token is sent to Google.
  factory AnalyticsTransport.direct({required String apiSecret}) =
      DirectTransport._;
}

/// The transport of [AnalyticsTransport.relay].
final class RelayTransport extends AnalyticsTransport {
  RelayTransport._(this.endpoint) : super._() {
    final bool secure = endpoint.scheme == 'https';
    final bool local =
        endpoint.scheme == 'http' && isLoopbackHost(endpoint.host);
    if (!secure && !local) {
      throw ArgumentError.value(
        '${endpoint.scheme}://${endpoint.host}',
        'endpoint',
        'A relay must use https, or http to a loopback host',
      );
    }
    if (endpoint.userInfo.isNotEmpty || endpoint.hasFragment) {
      throw ArgumentError(
        'A relay endpoint cannot carry user info or a fragment.',
        'endpoint',
      );
    }
  }

  /// The URL of the relay.
  final Uri endpoint;

  @override
  String toString() =>
      'AnalyticsTransport.relay(${endpoint.scheme}://${endpoint.authority}${endpoint.path})';
}

/// The transport of [AnalyticsTransport.direct]. Its secret is not readable from outside the package.
final class DirectTransport extends AnalyticsTransport {
  DirectTransport._({required String apiSecret})
    : _apiSecret = apiSecret,
      super._() {
    if (_apiSecret.isEmpty || _apiSecret.contains(RegExp(r'[\s\x00-\x1f]'))) {
      throw ArgumentError(
        'The API secret must be a non-empty string without spaces.',
        'apiSecret',
      );
    }
  }

  final String _apiSecret;

  @override
  String toString() => 'AnalyticsTransport.direct(apiSecret: <hidden>)';
}

/// Whether [host] names this machine.
@internal
bool isLoopbackHost(String host) {
  final String lower = host.toLowerCase();
  return lower == 'localhost' ||
      lower == '::1' ||
      lower == '[::1]' ||
      RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(lower);
}

/// The result of one attempt to send one request.
@internal
enum SendOutcome {
  /// A 2xx answer.
  delivered,

  /// An answer that says the request will never be accepted (a 4xx other than 429, or a redirect); the
  /// documentation says not to retry it.
  rejected,

  /// A network error, a timeout, 429 or 5xx: worth trying again later.
  retry,

  /// Not sent: the batch was no longer wanted when the request was about to leave.
  skipped,
}

/// Sends request bodies over a transport. It never reads, logs or rethrows anything that could carry the
/// API secret: the URL of a direct request holds it, and the message of an HTTP client error can quote the
/// URL, so only error types are reported.
@internal
class AnalyticsSender {
  AnalyticsSender({
    required this.transport,
    required this.app,
    required this.measurementId,
    required this.region,
    required this.warn,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
    this.tokenTimeout = const Duration(seconds: 10),
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  final AnalyticsTransport transport;
  final FirebaseApp app;
  final String measurementId;
  final AnalyticsRegion region;
  final void Function(String message) warn;
  final Duration timeout;

  /// How long a token provider may take before the request goes without that token.
  final Duration tokenTimeout;
  final http.Client _client;
  final bool _ownsClient;

  /// The largest part of an answer that is read before it is dropped.
  static const int maxResponseBytes = 16 * 1024;

  /// Sends one request body, once.
  ///
  /// The whole attempt (reading the tokens, sending, reading the answer) is bounded by [timeout]; a request
  /// still running then is aborted. [stillWanted] is asked once the tokens are read, just before the request
  /// leaves: when it answers false (collection was turned off, consent denied, the queue dropped or the client
  /// closed meanwhile), nothing is sent and the result is [SendOutcome.skipped].
  ///
  /// A request that times out may still have reached the endpoint, and its events are sent again later: the
  /// Measurement Protocol has no way to recognise a repeated request, so delivery is at least once.
  Future<SendOutcome> send(
    List<int> body, {
    required Future<bool> Function() stillWanted,
  }) async {
    final Completer<void> abort = Completer<void>();
    try {
      return await _attempt(body, stillWanted, abort.future).timeout(
        timeout,
        onTimeout: () {
          if (!abort.isCompleted) {
            abort.complete();
          }
          warn(
            'Analytics: the request did not finish within ${timeout.inSeconds} s; its events stay queued and '
            'are sent later.',
          );
          return SendOutcome.retry;
        },
      );
    } on Object catch (error) {
      // Only the type: the message of a ClientException quotes the URL, which holds the secret.
      warn(
        'Analytics: sending failed (${error.runtimeType}); the events stay queued and are sent later.',
      );
      return SendOutcome.retry;
    }
  }

  Future<SendOutcome> _attempt(
    List<int> body,
    Future<bool> Function() stillWanted,
    Future<void> abortTrigger,
  ) async {
    final Uri url;
    Map<String, String> headers = const <String, String>{};
    switch (transport) {
      case final RelayTransport relay:
        url = relay.endpoint.replace(
          queryParameters: <String, String>{
            ...relay.endpoint.queryParameters,
            ...ClientIdentity.streamQuery(measurementId),
          },
        );
        headers = await _relayHeaders(url);
      case final DirectTransport direct:
        url = Uri.https(region.host, '/mp/collect', <String, String>{
          ...ClientIdentity.streamQuery(measurementId),
          'api_secret': direct._apiSecret,
        });
    }
    if (!await stillWanted()) {
      return SendOutcome.skipped;
    }
    final http.AbortableRequest
    request = http.AbortableRequest('POST', url, abortTrigger: abortTrigger)
      // The protocol never redirects, and a redirect could carry tokens or the secret to another host.
      // In a browser, fetch reports a redirect as an error, so there it is retried until the events age
      // out instead of being dropped; it is still never followed.
      ..followRedirects = false
      ..headers.addAll(headers)
      ..headers['Content-Type'] = 'application/json'
      ..bodyBytes = body;
    final http.StreamedResponse response = await _client.send(request);
    await _drain(response);
    final int status = response.statusCode;
    if (status >= 200 && status < 300) {
      return SendOutcome.delivered;
    }
    if (status == 429 || status >= 500) {
      warn(
        'Analytics: the endpoint answered HTTP $status; the events stay queued and are sent later.',
      );
      return SendOutcome.retry;
    }
    warn(
      'Analytics: the endpoint answered HTTP $status; the events of a request of ${body.length} bytes were '
      'dropped, since a refused request is not retried.',
    );
    return SendOutcome.rejected;
  }

  Future<Map<String, String>> _relayHeaders(Uri url) async {
    final Map<String, String> headers = <String, String>{};
    final String appId = app.options.appId;
    if (_isHeaderSafe(appId)) {
      headers['X-Firebase-GMPID'] = appId;
    }
    if (!_mayCarryTokens(url)) {
      return headers;
    }
    final String? appCheck = await _appCheckToken();
    if (appCheck != null && _isHeaderSafe(appCheck)) {
      headers['X-Firebase-AppCheck'] = appCheck;
    }
    final String? idToken = await _idToken();
    if (idToken != null && _isHeaderSafe(idToken)) {
      headers['Authorization'] = 'Bearer $idToken';
    }
    return headers;
  }

  /// Tokens go only over https or to a loopback host (design rule 5 of contributing_a_product.md).
  static bool _mayCarryTokens(Uri url) =>
      url.scheme == 'https' || isLoopbackHost(url.host);

  /// Control characters in a header value could split the request; such a value is not sent.
  static bool _isHeaderSafe(String value) =>
      value.isNotEmpty && !value.contains(RegExp(r'[\x00-\x1f\x7f]'));

  Future<String?> _idToken() async {
    final AuthTokenProvider provider = app.authProvider;
    if (identical(provider, app)) {
      // The app is its own provider when none was set: nobody can be signed in.
      return null;
    }
    try {
      final GetTokenResult result = await provider
          .getAccessToken(forceRefresh: false)
          .timeout(tokenTimeout);
      return result.token.isEmpty ? null : result.token;
    } on FirebaseNoSignedInUserException {
      return null;
    } on FirebaseApiNotAvailableException {
      return null;
    } on Object catch (error) {
      // An event is not worth failing over; the relay decides what a request without a token gets.
      warn(
        'Analytics: the ID token could not be read (${error.runtimeType}); sending without it.',
      );
      return null;
    }
  }

  Future<String?> _appCheckToken() async {
    final AppCheckTokenProvider? provider = app.appCheckProvider;
    if (provider == null) {
      return null;
    }
    try {
      final AppCheckTokenResult result = await provider
          .getToken(forceRefresh: false)
          .timeout(tokenTimeout);
      return result.token.isEmpty ? null : result.token;
    } on Object {
      return null;
    }
  }

  static Future<void> _drain(http.StreamedResponse response) async {
    int read = 0;
    await for (final List<int> chunk in response.stream) {
      read += chunk.length;
      if (read >= maxResponseBytes) {
        break;
      }
    }
  }

  /// Closes the HTTP client when the sender created it.
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
