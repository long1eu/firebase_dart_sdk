// File created by
// Lung Razvan <long1eu>
// on 06/12/2019

part of requests;

/// Represents the response from the getProjectConfig endpoint.
abstract class GetProjectConfigResponse implements Built<GetProjectConfigResponse, GetProjectConfigResponseBuilder> {
  factory GetProjectConfigResponse() = _$GetProjectConfigResponse;

  factory GetProjectConfigResponse.fromJson(Map<dynamic, dynamic> json) =>
      serializers.deserializeWith(serializer, json);

  GetProjectConfigResponse._();

  /// The unique ID pertaining to the current project.
  @nullable
  String get projectId;

  /// A list of domains whitelisted for the current project.
  @nullable
  BuiltList<String> get authorizedDomains;

  static Serializer<GetProjectConfigResponse> get serializer => _$getProjectConfigResponseSerializer;
}
