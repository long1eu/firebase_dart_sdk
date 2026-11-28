part of 'probe_connector.dart';

class ListEverythingVariablesBuilder {
  Optional<Color> _color = Optional.optional((data) => Color.values.byName(data), enumSerializer);
  Optional<String> _opt = Optional.optional(nativeFromJson, nativeToJson);

  final FirebaseDataConnect _dataConnect;
  ListEverythingVariablesBuilder color(Color? t) {
   _color.value = t;
   return this;
  }
  ListEverythingVariablesBuilder opt(String? t) {
   _opt.value = t;
   return this;
  }

  ListEverythingVariablesBuilder(this._dataConnect, );
  Deserializer<ListEverythingData> dataDeserializer = (dynamic json)  => ListEverythingData.fromJson(jsonDecode(json));
  Serializer<ListEverythingVariables> varsSerializer = (ListEverythingVariables vars) => jsonEncode(vars.toJson());
  Future<QueryResult<ListEverythingData, ListEverythingVariables>> execute() {
    return ref().execute();
  }

  QueryRef<ListEverythingData, ListEverythingVariables> ref() {
    ListEverythingVariables vars= ListEverythingVariables(color: _color,opt: _opt,);
    return _dataConnect.query("ListEverything", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class ListEverythingEverythings {
  final String id;
  final String s;
  final int i;
  final double f;
  final bool b;
  final BigInt i64;
  final DateTime d;
  final Timestamp ts;
  final String u;
  final AnyValue? a;
  final EnumValue<Color> color;
  final List<EnumValue<Color>>? colors;
  final List<String>? tags;
  final String? opt;
  final ListEverythingEverythingsOwner owner;
  ListEverythingEverythings.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  s = nativeFromJson<String>(json['s']),
  i = nativeFromJson<int>(json['i']),
  f = nativeFromJson<double>(json['f']),
  b = nativeFromJson<bool>(json['b']),
  i64 = bigIntFromJson(json['i64']),
  d = nativeFromJson<DateTime>(json['d']),
  ts = Timestamp.fromJson(json['ts']),
  u = nativeFromJson<String>(json['u']),
  a = json['a'] == null ? null : AnyValue.fromJson(json['a']),
  color = colorDeserializer(json['color']),
  colors = json['colors'] == null ? null : (json['colors'] as List<dynamic>)
        .map((e) => colorDeserializer(e))
        .toList(),
  tags = json['tags'] == null ? null : (json['tags'] as List<dynamic>)
        .map((e) => nativeFromJson<String>(e))
        .toList(),
  opt = json['opt'] == null ? null : nativeFromJson<String>(json['opt']),
  owner = ListEverythingEverythingsOwner.fromJson(json['owner']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListEverythingEverythings otherTyped = other as ListEverythingEverythings;
    return id == otherTyped.id && 
    s == otherTyped.s && 
    i == otherTyped.i && 
    f == otherTyped.f && 
    b == otherTyped.b && 
    i64 == otherTyped.i64 && 
    d == otherTyped.d && 
    ts == otherTyped.ts && 
    u == otherTyped.u && 
    a == otherTyped.a && 
    color == otherTyped.color && 
    colors == otherTyped.colors && 
    tags == otherTyped.tags && 
    opt == otherTyped.opt && 
    owner == otherTyped.owner;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, s.hashCode, i.hashCode, f.hashCode, b.hashCode, i64.hashCode, d.hashCode, ts.hashCode, u.hashCode, a.hashCode, color.hashCode, colors.hashCode, tags.hashCode, opt.hashCode, owner.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['s'] = nativeToJson<String>(s);
    json['i'] = nativeToJson<int>(i);
    json['f'] = nativeToJson<double>(f);
    json['b'] = nativeToJson<bool>(b);
    json['i64'] = bigIntToJson(i64);
    json['d'] = nativeToJson<DateTime>(d);
    json['ts'] = ts.toJson();
    json['u'] = nativeToJson<String>(u);
    if (a != null) {
      json['a'] = a!.toJson();
    }
    json['color'] = 
    colorSerializer(color)
    ;
    if (colors != null) {
      json['colors'] = colors?.map((e) => colorSerializer(e)).toList();
    }
    if (tags != null) {
      json['tags'] = tags?.map((e) => nativeToJson<String>(e)).toList();
    }
    if (opt != null) {
      json['opt'] = nativeToJson<String?>(opt);
    }
    json['owner'] = owner.toJson();
    return json;
  }

  ListEverythingEverythings({
    required this.id,
    required this.s,
    required this.i,
    required this.f,
    required this.b,
    required this.i64,
    required this.d,
    required this.ts,
    required this.u,
    this.a,
    required this.color,
    this.colors,
    this.tags,
    this.opt,
    required this.owner,
  });
}

@immutable
class ListEverythingEverythingsOwner {
  final String id;
  final String name;
  ListEverythingEverythingsOwner.fromJson(dynamic json):
  
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

    final ListEverythingEverythingsOwner otherTyped = other as ListEverythingEverythingsOwner;
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

  ListEverythingEverythingsOwner({
    required this.id,
    required this.name,
  });
}

@immutable
class ListEverythingData {
  final List<ListEverythingEverythings> everythings;
  ListEverythingData.fromJson(dynamic json):
  
  everythings = (json['everythings'] as List<dynamic>)
        .map((e) => ListEverythingEverythings.fromJson(e))
        .toList();
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListEverythingData otherTyped = other as ListEverythingData;
    return everythings == otherTyped.everythings;
    
  }
  @override
  int get hashCode => everythings.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['everythings'] = everythings.map((e) => e.toJson()).toList();
    return json;
  }

  ListEverythingData({
    required this.everythings,
  });
}

@immutable
class ListEverythingVariables {
  late final Optional<Color>color;
  late final Optional<String>opt;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  ListEverythingVariables.fromJson(Map<String, dynamic> json) {
  
  
    color = Optional.optional((data) => Color.values.byName(data), enumSerializer);
    color.value = json['color'] == null ? null : Color.values.byName(json['color']);
  
  
    opt = Optional.optional(nativeFromJson, nativeToJson);
    opt.value = json['opt'] == null ? null : nativeFromJson<String>(json['opt']);
  
  }
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListEverythingVariables otherTyped = other as ListEverythingVariables;
    return color == otherTyped.color && 
    opt == otherTyped.opt;
    
  }
  @override
  int get hashCode => Object.hashAll([color.hashCode, opt.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    if(color.state == OptionalState.set) {
      json['color'] = color.toJson();
    }
    if(opt.state == OptionalState.set) {
      json['opt'] = opt.toJson();
    }
    return json;
  }

  ListEverythingVariables({
    required this.color,
    required this.opt,
  });
}

