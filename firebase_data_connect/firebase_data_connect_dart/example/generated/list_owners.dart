part of 'probe_connector.dart';

class ListOwnersVariablesBuilder {
  
  final FirebaseDataConnect _dataConnect;
  ListOwnersVariablesBuilder(this._dataConnect, );
  Deserializer<ListOwnersData> dataDeserializer = (dynamic json)  => ListOwnersData.fromJson(jsonDecode(json));
  
  Future<QueryResult<ListOwnersData, void>> execute() {
    return ref().execute();
  }

  QueryRef<ListOwnersData, void> ref() {
    
    return _dataConnect.query("ListOwners", dataDeserializer, emptySerializer, null);
  }
}

@immutable
class ListOwnersOwners {
  final String id;
  final String name;
  final List<ListOwnersOwnersEverythingsOnOwner> everythings_on_owner;
  ListOwnersOwners.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  name = nativeFromJson<String>(json['name']),
  everythings_on_owner = (json['everythings_on_owner'] as List<dynamic>)
        .map((e) => ListOwnersOwnersEverythingsOnOwner.fromJson(e))
        .toList();
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListOwnersOwners otherTyped = other as ListOwnersOwners;
    return id == otherTyped.id && 
    name == otherTyped.name && 
    everythings_on_owner == otherTyped.everythings_on_owner;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, name.hashCode, everythings_on_owner.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['name'] = nativeToJson<String>(name);
    json['everythings_on_owner'] = everythings_on_owner.map((e) => e.toJson()).toList();
    return json;
  }

  ListOwnersOwners({
    required this.id,
    required this.name,
    required this.everythings_on_owner,
  });
}

@immutable
class ListOwnersOwnersEverythingsOnOwner {
  final String id;
  final String s;
  ListOwnersOwnersEverythingsOnOwner.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  s = nativeFromJson<String>(json['s']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListOwnersOwnersEverythingsOnOwner otherTyped = other as ListOwnersOwnersEverythingsOnOwner;
    return id == otherTyped.id && 
    s == otherTyped.s;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, s.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['s'] = nativeToJson<String>(s);
    return json;
  }

  ListOwnersOwnersEverythingsOnOwner({
    required this.id,
    required this.s,
  });
}

@immutable
class ListOwnersData {
  final List<ListOwnersOwners> owners;
  ListOwnersData.fromJson(dynamic json):
  
  owners = (json['owners'] as List<dynamic>)
        .map((e) => ListOwnersOwners.fromJson(e))
        .toList();
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListOwnersData otherTyped = other as ListOwnersData;
    return owners == otherTyped.owners;
    
  }
  @override
  int get hashCode => owners.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['owners'] = owners.map((e) => e.toJson()).toList();
    return json;
  }

  ListOwnersData({
    required this.owners,
  });
}

