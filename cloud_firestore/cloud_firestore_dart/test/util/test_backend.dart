// Selection of the backend the integration tests talk to, from environment
// variables that the person running the tests sets:
//
//  * `FIRESTORE_EMULATOR_HOST` (`host:port`): the standard edition emulator.
//    When it is set it always wins, so a run that is meant for the emulator
//    can never reach a real project.
//  * `FIRESTORE_ENTERPRISE_EMULATOR_HOST` (`host:port`): a second emulator in
//    Enterprise edition, used only by the tests in `test/integration_enterprise`.
//  * `FIRESTORE_TEST_PROJECT_ID` (and optionally `FIRESTORE_TEST_DATABASE_ID`):
//    opt in to running against a real Firebase project. Requests are
//    authenticated with Application Default Credentials: the service-account
//    file named by `GOOGLE_APPLICATION_CREDENTIALS`, or the credentials of
//    `gcloud auth application-default login`. Nothing here creates, stores or
//    prints credentials.

import 'dart:io';

import 'package:grpc/grpc.dart'
    show BaseAuthenticator, applicationDefaultCredentialsAuthenticator;

/// A `host:port` pair of an emulator.
class EmulatorAddress {
  const EmulatorAddress(this.host, this.port);

  /// Parses `host:port`; the port defaults to [defaultPort] when it is absent.
  /// Throws a [FormatException] when the port is not a number.
  factory EmulatorAddress.parse(String value, {int defaultPort = 8080}) {
    final int separator = value.lastIndexOf(':');
    if (separator < 0) {
      return EmulatorAddress(value, defaultPort);
    }
    return EmulatorAddress(value.substring(0, separator),
        int.parse(value.substring(separator + 1)));
  }

  final String host;
  final int port;

  @override
  String toString() => '$host:$port';
}

/// The backend configuration read from an environment.
class TestBackend {
  /// Reads the configuration from [environment] (by default the environment
  /// of the process).
  TestBackend([Map<String, String>? environment])
      : _environment = environment ?? Platform.environment;

  static const String emulatorHostVariable = 'FIRESTORE_EMULATOR_HOST';
  static const String enterpriseEmulatorHostVariable =
      'FIRESTORE_ENTERPRISE_EMULATOR_HOST';
  static const String projectIdVariable = 'FIRESTORE_TEST_PROJECT_ID';
  static const String databaseIdVariable = 'FIRESTORE_TEST_DATABASE_ID';

  /// The host of production Firestore.
  static const String productionHost = 'firestore.googleapis.com';

  /// The OAuth scope requested for the real project.
  static const List<String> scopes = <String>[
    'https://www.googleapis.com/auth/datastore'
  ];

  final Map<String, String> _environment;

  String? _value(String name) {
    final String? value = _environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// The `host:port` of the standard emulator, or null.
  String? get emulatorHost => _value(emulatorHostVariable);

  /// The `host:port` of the Enterprise edition emulator, or null.
  String? get enterpriseEmulatorHost => _value(enterpriseEmulatorHostVariable);

  /// The reason to skip tests that need the Enterprise edition emulator, or
  /// null when it is configured. Pass it to `skip:`.
  String? get enterpriseEmulatorSkipReason => enterpriseEmulatorHost != null
      ? null
      : '$enterpriseEmulatorHostVariable is not set (start the emulator with '
          'tool/start_enterprise_emulator.sh and export it)';

  /// Whether the tests run against a real Firebase project: the project id
  /// variable is set and no standard emulator is configured.
  bool get usesRealProject => emulatorHost == null && realProjectId != null;

  /// The id of the real project, or null. Ignored while [emulatorHost] is set.
  String? get realProjectId => _value(projectIdVariable);

  /// The database id to use in the real project, or null for `(default)`.
  String? get realDatabaseId =>
      usesRealProject ? _value(databaseIdVariable) : null;
}

/// Fetches OAuth access tokens with Application Default Credentials.
///
/// The credentials are looked up by `package:grpc` (first the file named by
/// `GOOGLE_APPLICATION_CREDENTIALS`, then the gcloud application default
/// credentials file, then the metadata server); tokens are cached and
/// refreshed by it. The token is only ever handed to the gRPC call
/// credentials, it is never logged.
class ApplicationDefaultTokenSource {
  ApplicationDefaultTokenSource(
      {Future<BaseAuthenticator> Function(List<String> scopes)?
          createAuthenticator})
      : _createAuthenticator =
            createAuthenticator ?? applicationDefaultCredentialsAuthenticator;

  final Future<BaseAuthenticator> Function(List<String> scopes)
      _createAuthenticator;
  Future<BaseAuthenticator>? _authenticator;

  static const String _bearer = 'Bearer ';

  /// The current access token.
  Future<String?> get token async {
    final BaseAuthenticator authenticator =
        await (_authenticator ??= _createAuthenticator(TestBackend.scopes));
    final Map<String, String> metadata = <String, String>{};
    await authenticator.authenticate(
        metadata, 'https://${TestBackend.productionHost}/');
    final String? header = metadata['authorization'];
    if (header == null || !header.startsWith(_bearer)) {
      throw StateError(
          'Application Default Credentials did not produce a bearer token.');
    }
    return header.substring(_bearer.length);
  }

  /// Drops the authenticator, so that the next [token] starts from the
  /// credentials again.
  void invalidate() => _authenticator = null;
}
