part of 'probe_connector.dart';

class CreateOwnerVariablesBuilder {
  String name;

  final FirebaseDataConnect _dataConnect;
  CreateOwnerVariablesBuilder(this._dataConnect, {required  this.name,});
  Deserializer<CreateOwnerData> dataDeserializer = (dynamic json)  => CreateOwnerData.fromJson(jsonDecode(json));
  Serializer<CreateOwnerVariables> varsSerializer = (CreateOwnerVariables vars) => jsonEncode(vars.toJson());
  Future<OperationResult<CreateOwnerData, CreateOwnerVariables>> execute() {
    return ref().execute();
  }

  MutationRef<CreateOwnerData, CreateOwnerVariables> ref() {
    CreateOwnerVariables vars= CreateOwnerVariables(name: name,);
    return _dataConnect.mutation("CreateOwner", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class CreateOwnerOwnerInsert {
  final String id;
  CreateOwnerOwnerInsert.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateOwnerOwnerInsert otherTyped = other as CreateOwnerOwnerInsert;
    return id == otherTyped.id;
    
  }
  @override
  int get hashCode => id.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    return json;
  }

  CreateOwnerOwnerInsert({
    required this.id,
  });
}

@immutable
class CreateOwnerData {
  final CreateOwnerOwnerInsert owner_insert;
  CreateOwnerData.fromJson(dynamic json):
  
  owner_insert = CreateOwnerOwnerInsert.fromJson(json['owner_insert']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateOwnerData otherTyped = other as CreateOwnerData;
    return owner_insert == otherTyped.owner_insert;
    
  }
  @override
  int get hashCode => owner_insert.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['owner_insert'] = owner_insert.toJson();
    return json;
  }

  CreateOwnerData({
    required this.owner_insert,
  });
}

@immutable
class CreateOwnerVariables {
  final String name;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  CreateOwnerVariables.fromJson(Map<String, dynamic> json):
  
  name = nativeFromJson<String>(json['name']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateOwnerVariables otherTyped = other as CreateOwnerVariables;
    return name == otherTyped.name;
    
  }
  @override
  int get hashCode => name.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['name'] = nativeToJson<String>(name);
    return json;
  }

  CreateOwnerVariables({
    required this.name,
  });
}

