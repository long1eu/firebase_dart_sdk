/// The seam between `DataConnect` and the two transports (gRPC on the VM, REST on the web).
///
/// Internal: none of these types is exported.
library;

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_data_connect_dart/src/api/connector_config.dart';
import 'package:firebase_data_connect_dart/src/errors.dart';
import 'package:firebase_data_connect_dart/src/version.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// The two kinds of operation.
enum OperationKind {
  /// `ExecuteQuery` / `:executeQuery`.
  query,

  /// `ExecuteMutation` / `:executeMutation`.
  mutation,
}

/// The production host of Data Connect.
const String productionHost = 'firebasedataconnect.googleapis.com';

/// The production port.
const int productionPort = 443;

/// The largest response body or message either transport accepts: 16 MiB.
const int maxResponseBytes = 16 * 1024 * 1024;

/// The target an instance talks to, and the values its requests carry.
@immutable
final class TransportConfig {
  /// A target at [host]:[port], over TLS when [secure].
  const TransportConfig({
    required this.host,
    required this.port,
    required this.secure,
    required this.connectorResourceName,
    required this.location,
    required this.projectId,
    required this.serviceId,
    required this.appId,
    required this.apiKey,
    required this.callerSdkType,
    this.httpClient,
  });

  /// The host: [productionHost], or the emulator's host (an IPv6 address without brackets).
  final String host;

  /// The port.
  final int port;

  /// Whether the connection uses TLS.
  final bool secure;

  /// `projects/{p}/locations/{l}/services/{s}/connectors/{c}`.
  final String connectorResourceName;

  /// The location of the service.
  final String location;

  /// The project id of the app.
  final String projectId;

  /// The service id.
  final String serviceId;

  /// The app id as the app's options hold it; checked by the transport before it is sent.
  final String? appId;

  /// The API key as the app's options hold it; REST only.
  final String? apiKey;

  /// Who calls the operations.
  final CallerSdkType callerSdkType;

  /// The HTTP client of the REST transport; not closed by the transport. Null: the transport
  /// creates one and closes it in [OperationTransport.close].
  final http.Client? httpClient;

  /// `Uri(scheme: secure ? 'https' : 'http', host: host, port: port)`; on the VM this is
  /// `GrpcTarget.origin`.
  Uri get origin =>
      Uri(scheme: secure ? 'https' : 'http', host: host, port: port);

  /// The value of `x-goog-api-client`: `apiClientHeader` with [extra], then `dart/gen` for
  /// generated callers.
  String apiClient({List<String> extra = const <String>[]}) => apiClientHeader(
    sdkVersion: packageVersion,
    extra: <String>[
      ...extra,
      if (callerSdkType == CallerSdkType.generated) 'dart/gen',
    ],
  );

  /// The value of `x-client-version`: `dart/<package version>`.
  String get clientVersion => 'dart/$packageVersion';

  /// The app id, checked for the `x-firebase-gmpid` header.
  ///
  /// Throws a [StateError] naming the option when it is null or empty, and an [ArgumentError]
  /// naming it (never the value) when it is not a header value.
  String checkedAppId() {
    final String? value = appId;
    if (value == null || value.isEmpty) {
      throw StateError(
        'FirebaseOptions.appId is empty; Data Connect sends it with every call.',
      );
    }
    if (!isHeaderValue(value)) {
      throw ArgumentError(
        'is not a valid header value',
        'FirebaseOptions.appId',
      );
    }
    return value;
  }
}

/// One transport of one instance. Created on the first call; closed by `DataConnect.close()`.
abstract interface class OperationTransport {
  /// The URL `TokenSource.tokensFor` is called with for this attempt: [TransportConfig.origin] on
  /// the VM, the request URL (same origin, without its query) on the web.
  Uri tokenUrl(OperationKind kind);

  /// Sends one attempt of the operation [operationName] with [variables] (already checked), within
  /// [timeout].
  ///
  /// [tokens] are applied once, to this attempt only. Never throws for a server or network failure:
  /// returns a [WireFailure]. A [StateError] from applying [tokens] (another origin, or used
  /// before) is a defect and is rethrown unchanged, as are the [StateError] and [ArgumentError] of
  /// a missing or malformed app id or API key.
  Future<WireResult> execute(
    OperationKind kind,
    String operationName,
    Map<String, Object?>? variables,
    RequestTokens tokens, {
    required Duration timeout,
  });

  /// Releases the connection. Calls in flight end with [RpcStatus.cancelled].
  Future<void> close();
}

/// What one attempt returned.
sealed class WireResult {
  const WireResult();
}

/// The server answered with transport status OK.
final class WireResponse extends WireResult {
  /// A response with [data] and [errors].
  const WireResponse({this.data, required this.errors});

  /// The `data` object, with data depth at most 100; null when absent or JSON null.
  final Map<String, Object?>? data;

  /// The GraphQL errors; empty when there are none.
  final List<GraphqlError> errors;
}

/// The attempt failed: a status other than OK, or a response that could not be read.
final class WireFailure extends WireResult {
  /// A failure with [status].
  const WireFailure(
    this.status, {
    this.invalidResponse = false,
    this.serverMessage,
  });

  /// The status.
  final RpcStatus status;

  /// True when the response could not be read (too large, malformed, too deep); reported as
  /// `invalid-response`.
  final bool invalidResponse;

  /// The server's message through `sanitizeServerText`; null when it sent none.
  final String? serverMessage;
}
