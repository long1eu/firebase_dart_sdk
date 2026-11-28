import 'dart:async';
import 'dart:convert';

import 'package:firebase_remote_config_dart/src/bounded.dart';
import 'package:firebase_remote_config_dart/src/exception.dart';
import 'package:firebase_remote_config_dart/src/http_rules.dart';
import 'package:firebase_remote_config_dart/src/json_guard.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:firebase_remote_config_dart/src/version.dart';
import 'package:http/http.dart' as http;

/// The largest success body of a fetch, in bytes (5.11 rule 7).
const int fetchSuccessCap = 8 * 1024 * 1024;

/// The largest error body read, in bytes (5.11 rule 7).
const int errorBodyCap = 16 * 1024;

/// What one fetch request produced.
sealed class FetchOutcome {
  const FetchOutcome();
}

/// The server sent a template (`UPDATE`, no `state`, `NO_TEMPLATE` or `EMPTY_CONFIG`).
final class FetchUpdated extends FetchOutcome {
  /// Creates the outcome for [record].
  const FetchUpdated(this.record);

  /// The template to store as the fetched record.
  final TemplateRecord record;
}

/// The server said the stored template is current (`NO_CHANGE`, `INSTANCE_STATE_UNSPECIFIED`, or 304).
final class FetchUnchanged extends FetchOutcome {
  /// Creates the outcome.
  const FetchUnchanged();
}

/// The request failed.
final class FetchFailed extends FetchOutcome {
  /// Creates the outcome for [error].
  const FetchFailed(this.error);

  /// The error; `httpStatus` is set when a response arrived.
  final FirebaseRemoteConfigException error;
}

/// The parts of one fetch request that change between calls.
final class FetchRequest {
  /// Creates the parts of a request.
  const FetchRequest({
    required this.installationId,
    required this.installationToken,
    required this.languageCode,
    required this.customSignals,
    required this.fetchType,
    required this.deadline,
    this.etag,
  });

  /// The FID, sent as `app_instance_id`.
  final String installationId;

  /// The auth token of the FID, sent in the body and in `X-Goog-Firebase-Installations-Auth`.
  final String installationToken;

  /// The `language_code` of the body.
  final String languageCode;

  /// The custom signals; left out of the body when empty.
  final Map<String, String> customSignals;

  /// The `X-Firebase-RC-Fetch-Type` header: `BASE/1` or `REALTIME/<attempt>`.
  final String fetchType;

  /// The time left for the request.
  final Duration deadline;

  /// The `If-None-Match` header, when the caller allows one.
  final String? etag;
}

/// Sends the fetch request of 5.5 and reads its answer.
final class FetchClient {
  /// Creates a client for the project of [projectId].
  FetchClient({
    required http.Client client,
    required Uri origin,
    required String projectId,
    required String apiKey,
    required String appId,
    required Map<String, String> extraHeaders,
    required DateTime Function() clock,
    DropReporter? onDrop,
  }) : _client = client,
       _apiKey = apiKey,
       _appId = appId,
       _extraHeaders = extraHeaders,
       _clock = clock,
       _onDrop = onDrop,
       _url = origin.replace(
         pathSegments: <String>[
           'v1',
           'projects',
           projectId,
           'namespaces',
           'firebase:fetch',
         ],
       );

  final http.Client _client;
  final String _apiKey;
  final String _appId;
  final Map<String, String> _extraHeaders;
  final DateTime Function() _clock;
  final Set<Completer<void>> _active = <Completer<void>>{};
  final DropReporter? _onDrop;
  final Uri _url;

  /// Sends [request] and returns its outcome; it never throws.
  Future<FetchOutcome> fetch(FetchRequest request) async {
    final Completer<void> cancel = Completer<void>();
    _active.add(cancel);
    final CappedResponse response;
    try {
      response = await sendCapped(
        _client,
        (Future<void> abort) =>
            _build(request, Future.any(<Future<void>>[abort, cancel.future])),
        successCap: fetchSuccessCap,
        errorCap: errorBodyCap,
        deadline: request.deadline,
      );
    } on TimeoutException {
      return const FetchFailed(
        FirebaseRemoteConfigException(
          code: 'fetch-timeout',
          message: 'The fetch did not complete before its timeout.',
        ),
      );
    } on CapExceededException {
      return const FetchFailed(
        FirebaseRemoteConfigException(
          code: 'fetch-client-parse',
          message: 'The fetch response is larger than 8 MiB.',
        ),
      );
    } catch (error) {
      return FetchFailed(
        FirebaseRemoteConfigException(
          code: 'fetch-client-network',
          message: 'The fetch request failed before a response arrived.',
          cause: error,
        ),
      );
    } finally {
      _active.remove(cancel);
    }
    return _read(response);
  }

  /// Aborts every request in flight; each returns `fetch-client-network`.
  void abortAll() {
    for (final Completer<void> cancel in _active.toList()) {
      if (!cancel.isCompleted) {
        cancel.complete();
      }
    }
  }

  http.BaseRequest _build(FetchRequest request, Future<void> abort) {
    final http.AbortableRequest built =
        http.AbortableRequest('POST', _url, abortTrigger: abort)
          ..headers.addAll(<String, String>{
            ..._extraHeaders,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Goog-Api-Key': _apiKey,
            'X-Goog-Firebase-Installations-Auth': request.installationToken,
            'X-Firebase-RC-Fetch-Type': request.fetchType,
            'If-None-Match': ?request.etag,
          })
          // bodyBytes leaves Content-Type as set; `body` would add a charset.
          ..bodyBytes = utf8.encode(jsonEncode(_body(request)));
    return built;
  }

  Map<String, Object?> _body(FetchRequest request) => <String, Object?>{
    'sdk_version': packageVersion,
    'app_instance_id': request.installationId,
    'app_instance_id_token': request.installationToken,
    'app_id': _appId,
    'language_code': request.languageCode,
    if (request.customSignals.isNotEmpty)
      'custom_signals': request.customSignals,
  };

  FetchOutcome _read(CappedResponse response) {
    final int status = response.statusCode;
    if (status == 304) {
      return const FetchUnchanged();
    }
    if (status != 200) {
      return FetchFailed(_statusError(response));
    }
    try {
      return _parseSuccess(response);
    } on FormatException {
      return const FetchFailed(
        FirebaseRemoteConfigException(
          code: 'fetch-client-parse',
          message: 'The fetch response is not the JSON the client expects.',
          httpStatus: 200,
        ),
      );
    }
  }

  FetchOutcome _parseSuccess(CappedResponse response) {
    final Map<String, Object?>? json = asObject(
      decodeGuardedBytes(response.body),
    );
    if (json == null) {
      throw const FormatException('not an object');
    }
    final Object? state = json['state'];
    if (state != null && state is! String) {
      throw const FormatException('state');
    }
    Map<String, String> entries = const <String, String>{};
    if (json.containsKey('entries')) {
      entries =
          asStringMap(json['entries']) ??
          (throw const FormatException('entries'));
    }
    int? version;
    if (json.containsKey('templateVersion')) {
      version =
          parseBoundedInt(
            json['templateVersion'],
            min: 0,
            max: maxSafeInteger,
          ) ??
          (throw const FormatException('templateVersion'));
    }
    switch (state) {
      case null || 'UPDATE':
        return FetchUpdated(_record(response, json, entries, version));
      case 'NO_TEMPLATE' || 'EMPTY_CONFIG':
        // No values, but the version and ETag the server sent are kept: the realtime target and the
        // version rule of activate compare against them.
        return FetchUpdated(
          _record(
            response,
            const <String, Object?>{},
            const <String, String>{},
            version,
          ),
        );
      case 'NO_CHANGE' || 'INSTANCE_STATE_UNSPECIFIED':
        return const FetchUnchanged();
      default:
        throw const FormatException('unknown state');
    }
  }

  TemplateRecord _record(
    CappedResponse response,
    Map<String, Object?> metadata,
    Map<String, String> entries,
    int? version,
  ) {
    final String? etag = response.headers['etag'];
    return TemplateRecord(
      entries: entries,
      fetchTime: _clock(),
      etag: etag == null ? null : validEtag(etag),
      templateVersion: version,
      experimentDescriptions: readExperiments(
        metadata['experimentDescriptions'],
        _onDrop,
      ),
      rolloutMetadata: readRollouts(metadata['rolloutMetadata'], _onDrop),
      personalizationMetadata: readPersonalization(
        metadata['personalizationMetadata'],
        _onDrop,
      ),
    );
  }

  FirebaseRemoteConfigException _statusError(CappedResponse response) {
    final int status = response.statusCode;
    final ServerError server = parseServerError(response);
    final bool redirect = status >= 300 && status < 400;
    return FirebaseRemoteConfigException(
      code: status == 429 ? 'fetch-throttle' : 'fetch-status',
      message: redirect
          ? 'The fetch was answered with a redirect, which the client does not follow.'
          : 'The fetch failed with HTTP $status.',
      httpStatus: status,
      serverStatus: server.status,
      serverMessage: server.message,
    );
  }
}

/// The `error.status` and `error.message` of an error body, sanitized.
typedef ServerError = ({String? status, String? message});

/// Reads `{"error": {"code", "status", "message"}}` or `{"error": "<text>"}` from an error body; a body
/// that is neither gives nulls.
ServerError parseServerError(CappedResponse response) {
  final Object? decoded;
  try {
    decoded = decodeGuardedText(decodeLenient(response.body));
  } on FormatException {
    return (status: null, message: null);
  }
  final Object? error = asObject(decoded)?['error'];
  if (error is String) {
    return (status: null, message: sanitizeServerText(error));
  }
  final Map<String, Object?>? object = asObject(error);
  if (object == null) {
    return (status: null, message: null);
  }
  final Object? status = object['status'];
  final Object? message = object['message'];
  return (
    status: status is String ? sanitizeServerText(status) : null,
    message: message is String ? sanitizeServerText(message) : null,
  );
}
