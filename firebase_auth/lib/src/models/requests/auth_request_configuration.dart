// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

part of requests;

abstract class AuthRequestConfiguration implements Built<AuthRequestConfiguration, AuthRequestConfigurationBuilder> {
  factory AuthRequestConfiguration({String apiKey, String languageCode}) {
    return _$AuthRequestConfiguration((AuthRequestConfigurationBuilder b) {
      b
        ..apiKey = apiKey
        ..languageCode = languageCode;
    });
  }

  factory AuthRequestConfiguration.fromJson(Map<dynamic, dynamic> json) =>
      serializers.deserializeWith(serializer, json);

  AuthRequestConfiguration._();

  /// The Firebase Auth API key used in the request.
  String get apiKey;

  /// The language code used in the request.
  String get languageCode;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<AuthRequestConfiguration> get serializer => _$authRequestConfigurationSerializer;
}
