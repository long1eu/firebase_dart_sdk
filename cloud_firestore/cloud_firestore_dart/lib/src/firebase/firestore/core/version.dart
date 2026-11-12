// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

/// Holds static version string of the SDK. Both values go into the
/// `x-goog-api-client` header of every request.
class Version {
  /// The version of this package. Must be the `version` of `pubspec.yaml`
  /// (checked by `test/unit/firebase/firestore/core/version_test.dart`).
  static const String sdkVersion = '0.1.0';

  /// The version of `package:grpc` this package is developed with: the one
  /// in `pubspec.lock` (checked by the same test).
  static const String grpcVersion = '5.2.0';
}
