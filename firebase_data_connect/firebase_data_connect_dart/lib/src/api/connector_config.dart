import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:meta/meta.dart';

/// The connector a `DataConnect` instance calls: its location, service and connector ids.
///
/// Each part must be 1 to 63 characters of `a-z`, `0-9` and `-`, not starting or ending with `-`.
/// The parts are checked when a `DataConnect` is created, which throws an [ArgumentError] naming
/// the part (never its value) for one that is not.
@immutable
final class ConnectorConfig {
  /// The connector [connector] of the service [serviceId] in [location].
  const ConnectorConfig({
    required this.location,
    required this.serviceId,
    required this.connector,
  });

  /// The region of the service, for example `us-central1`.
  final String location;

  /// The id of the Data Connect service.
  final String serviceId;

  /// The id of the connector.
  final String connector;

  /// Throws an [ArgumentError] naming the first part that is not a host label.
  @internal
  void check() {
    _checkPart(location, 'location');
    _checkPart(serviceId, 'serviceId');
    _checkPart(connector, 'connector');
  }

  /// `projects/{projectId}/locations/{location}/services/{serviceId}/connectors/{connector}`.
  ///
  /// [projectId] is the app's project id, already checked by the caller.
  @internal
  String resourceName(String projectId) =>
      'projects/$projectId/locations/$location/services/$serviceId/connectors/$connector';

  static void _checkPart(String value, String name) {
    if (!isHostLabel(value)) {
      throw ArgumentError(
        'must be 1 to 63 characters of a-z, 0-9 and -, not starting or ending with -',
        'ConnectorConfig.$name',
      );
    }
  }
}

/// Who calls the operations of an instance; it changes only the `x-goog-api-client` header.
enum CallerSdkType {
  /// Application code calls the API directly.
  base,

  /// Code produced by the Data Connect code generator calls it (` dart/gen` is added to the
  /// header).
  generated,
}
