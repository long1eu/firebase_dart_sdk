// File created by
// Lung Razvan <long1eu>
// on 07/12/2019

part of requests;

/// A class represents a credential that proves the identity of the app.
abstract class AppCredential implements Built<AppCredential, AppCredentialBuilder> {
  factory AppCredential({@required String receipt, @required String secret}) {
    return _$AppCredential((AppCredentialBuilder b) {
      b
        ..receipt = receipt
        ..secret = secret;
    });
  }

  AppCredential._();

  /// The server acknowledgement of receiving client's claim of identity.
  String get receipt;

  /// The secret that the client received from server via a trusted channel, if ever.
  String get secret;
}
