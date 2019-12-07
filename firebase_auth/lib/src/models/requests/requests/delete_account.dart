// File created by
// Lung Razvan <long1eu>
// on 05/12/2019

part of requests;

/// Represents the parameters for the deleteAccount endpoint.
///
/// see https://developers.google.com/identity/toolkit/web/reference/relyingparty/deleteAccount
abstract class DeleteAccountRequest implements Built<DeleteAccountRequest, DeleteAccountRequestBuilder> {
  factory DeleteAccountRequest({@required String accessToken, @required String localId}) {
    return _$DeleteAccountRequest((DeleteAccountRequestBuilder b) {
      b
        ..accessToken = accessToken
        ..localId = localId;
    });
  }

  DeleteAccountRequest._();

  /// The STS Access Token of the authenticated user.
  ///
  /// This is actually the STS Access Token, despite it's confusing (backwards compatiable) wireName.
  @BuiltValueField(wireName: 'idToken')
  String get accessToken;

  /// The localId of the user.
  String get localId;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<DeleteAccountRequest> get serializer => _$deleteAccountRequestSerializer;
}
