// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of models;

abstract class CreateAuthUriRequest implements Built<CreateAuthUriRequest, CreateAuthUriRequestBuilder> {
  factory CreateAuthUriRequest({
    @required String identifier,
    @required String continueUri,
  }) {
    return _$CreateAuthUriRequest((CreateAuthUriRequestBuilder b) {
      b
        ..identifier = identifier
        ..continueUri = continueUri;
    });
  }

  CreateAuthUriRequest._();

  /// User's email address
  String get identifier;

  /// The URI to which the IDP redirects the user back.
  ///
  /// For this use case, this is just the current URL.
  String get continueUri;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<CreateAuthUriRequest> get serializer => _$createAuthUriRequestSerializer;
}

abstract class CreateAuthUriResponse implements Built<CreateAuthUriResponse, CreateAuthUriResponseBuilder> {
  factory CreateAuthUriResponse() = _$CreateAuthUriResponse;

  factory CreateAuthUriResponse.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  CreateAuthUriResponse._();

  @nullable
  BuiltList<String> get allProviders;

  bool get registered;

  static Serializer<CreateAuthUriResponse> get serializer => _$createAuthUriResponseSerializer;
}
