/// The REST transport, used on the web (spec 5.5).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_data_connect_dart/src/transport/rest/rest_decode.dart';
import 'package:firebase_data_connect_dart/src/transport/transport.dart';
import 'package:http/http.dart' as http;

/// The cap on a non-2xx body: 16 KiB.
const int _errorCap = 16 * 1024;

/// Sends each attempt as `POST .../connectors/<c>:executeQuery` (or `:executeMutation`) with a JSON
/// body, through `sendCapped`: no redirects, capped bodies, aborted at the deadline.
final class RestTransport implements OperationTransport {
  /// A transport for [config]; it uses [TransportConfig.httpClient], or a client of its own that
  /// [close] closes.
  RestTransport(TransportConfig config)
    : _config = config,
      _client = config.httpClient ?? http.Client(),
      _ownsClient = config.httpClient == null;

  final TransportConfig _config;
  final http.Client _client;
  final bool _ownsClient;
  final Set<Completer<void>> _active = <Completer<void>>{};
  bool _closed = false;

  /// The request URL without its query. Throws the [StateError] of a missing API key or app id, so
  /// that nothing is asked of the token providers for a call that cannot be sent.
  @override
  Uri tokenUrl(OperationKind kind) {
    _apiKey();
    _config.checkedAppId();
    return _endpoint(kind);
  }

  @override
  Future<WireResult> execute(
    OperationKind kind,
    String operationName,
    Map<String, Object?>? variables,
    RequestTokens tokens, {
    required Duration timeout,
  }) async {
    final Uri url = _endpoint(
      kind,
    ).replace(queryParameters: <String, String>{'key': _apiKey()});
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      FirebaseHeaders.apiClient: _config.apiClient(),
      'X-Client-Version': _config.clientVersion,
      FirebaseHeaders.gmpId: _config.checkedAppId(),
    };
    final Uint8List body = utf8.encode(
      jsonEncode(<String, Object?>{
        'name': _config.connectorResourceName,
        'operationName': operationName,
        'variables': ?variables,
      }),
    );
    if (_closed) {
      return const WireFailure(RpcStatus.cancelled);
    }
    return _send(url, headers, body, tokens, timeout);
  }

  Future<WireResult> _send(
    Uri url,
    Map<String, String> headers,
    Uint8List body,
    RequestTokens tokens,
    Duration timeout,
  ) async {
    final Completer<void> cancel = Completer<void>();
    _active.add(cancel);
    try {
      final CappedResponse response = await sendCapped(
        _client,
        (Future<void> abort) => _request(url, headers, body, tokens, abort),
        successCap: maxResponseBytes,
        errorCap: _errorCap,
        deadline: timeout,
        cancel: cancel.future,
      );
      if (response.isSuccess) {
        return decodeSuccessBody(response.body);
      }
      return decodeErrorBody(response.statusCode, response.body);
    } on CapExceededException {
      return const WireFailure(RpcStatus.internal, invalidResponse: true);
    } on TransportException catch (error) {
      return WireFailure(rpcStatusOfFailure(error));
    } on TimeoutException catch (error) {
      return WireFailure(rpcStatusOfFailure(error));
    } finally {
      _active.remove(cancel);
    }
  }

  /// The request; [applyTokens] puts the token headers on it, checked against its URL. Its
  /// [StateError] (tokens of another origin, or used before) is a defect and propagates.
  http.BaseRequest _request(
    Uri url,
    Map<String, String> headers,
    Uint8List body,
    RequestTokens tokens,
    Future<void> abort,
  ) {
    final http.AbortableRequest request =
        http.AbortableRequest('POST', url, abortTrigger: abort)
          ..headers.addAll(headers)
          // bodyBytes leaves Content-Type as set; `body` would add a charset.
          ..bodyBytes = body;
    applyTokens(request, tokens, auth: AuthHeaderStyle.firebaseAuthToken);
    return request;
  }

  Uri _endpoint(OperationKind kind) {
    final String method = switch (kind) {
      OperationKind.query => 'executeQuery',
      OperationKind.mutation => 'executeMutation',
    };
    final List<String> segments = <String>[
      'v1',
      ..._config.connectorResourceName.split('/'),
    ];
    segments.last = '${segments.last}:$method';
    return _config.origin.replace(pathSegments: segments);
  }

  String _apiKey() {
    final String? apiKey = _config.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError(
        'FirebaseOptions.apiKey is empty; Data Connect sends it with every call on the web.',
      );
    }
    return apiKey;
  }

  /// Aborts the calls in flight (they end [RpcStatus.cancelled]) and closes the HTTP client if this
  /// transport created it.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final Completer<void> cancel in _active.toList()) {
      if (!cancel.isCompleted) {
        cancel.complete();
      }
    }
    if (_ownsClient) {
      _client.close();
    }
  }
}
