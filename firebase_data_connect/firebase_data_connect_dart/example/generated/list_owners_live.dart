part of 'probe_connector.dart';

class ListOwnersLiveVariablesBuilder {
  
  final FirebaseDataConnect _dataConnect;
  ListOwnersLiveVariablesBuilder(this._dataConnect, );
  Deserializer<ListOwnersLiveData> dataDeserializer = (dynamic json)  => ListOwnersLiveData.fromJson(jsonDecode(json));
  
  Future<QueryResult<ListOwnersLiveData, void>> execute() {
    return ref().execute();
  }

  QueryRef<ListOwnersLiveData, void> ref() {
    
    return _dataConnect.query("ListOwnersLive", dataDeserializer, emptySerializer, null);
  }
}

@immutable
class ListOwnersLiveOwners {
  final String id;
  final String name;
  ListOwnersLiveOwners.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  name = nativeFromJson<String>(json['name']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListOwnersLiveOwners otherTyped = other as ListOwnersLiveOwners;
    return id == otherTyped.id && 
    name == otherTyped.name;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, name.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['name'] = nativeToJson<String>(name);
    return json;
  }

  ListOwnersLiveOwners({
    required this.id,
    required this.name,
  });
}

@immutable
class ListOwnersLiveData {
  final List<ListOwnersLiveOwners> owners;
  ListOwnersLiveData.fromJson(dynamic json):
  
  owners = (json['owners'] as List<dynamic>)
        .map((e) => ListOwnersLiveOwners.fromJson(e))
        .toList();
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListOwnersLiveData otherTyped = other as ListOwnersLiveData;
    return owners == otherTyped.owners;
    
  }
  @override
  int get hashCode => owners.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['owners'] = owners.map((e) => e.toJson()).toList();
    return json;
  }

  ListOwnersLiveData({
    required this.owners,
  });
}

