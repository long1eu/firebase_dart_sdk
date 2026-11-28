part of 'probe_connector.dart';

class CreateEverythingVariablesBuilder {
  String s;
  int i;
  double f;
  bool b;
  BigInt i64;
  DateTime d;
  Timestamp ts;
  String u;
  Optional<AnyValue> _a = Optional.optional(AnyValue.fromJson, defaultSerializer);
  Color color;
  Optional<List<Color>> _colors = Optional.optional(listDeserializer((data) => Color.values.byName(data)), listSerializer(enumSerializer));
  Optional<List<String>> _tags = Optional.optional(listDeserializer(nativeFromJson), listSerializer(nativeToJson));
  String ownerId;
  Optional<String> _opt = Optional.optional(nativeFromJson, nativeToJson);

  final FirebaseDataConnect _dataConnect;  CreateEverythingVariablesBuilder a(AnyValue? t) {
   _a.value = t;
   return this;
  }
  CreateEverythingVariablesBuilder colors(List<Color>? t) {
   _colors.value = t;
   return this;
  }
  CreateEverythingVariablesBuilder tags(List<String>? t) {
   _tags.value = t;
   return this;
  }
  CreateEverythingVariablesBuilder opt(String? t) {
   _opt.value = t;
   return this;
  }

  CreateEverythingVariablesBuilder(this._dataConnect, {required  this.s,required  this.i,required  this.f,required  this.b,required  this.i64,required  this.d,required  this.ts,required  this.u,required  this.color,required  this.ownerId,});
  Deserializer<CreateEverythingData> dataDeserializer = (dynamic json)  => CreateEverythingData.fromJson(jsonDecode(json));
  Serializer<CreateEverythingVariables> varsSerializer = (CreateEverythingVariables vars) => jsonEncode(vars.toJson());
  Future<OperationResult<CreateEverythingData, CreateEverythingVariables>> execute() {
    return ref().execute();
  }

  MutationRef<CreateEverythingData, CreateEverythingVariables> ref() {
    CreateEverythingVariables vars= CreateEverythingVariables(s: s,i: i,f: f,b: b,i64: i64,d: d,ts: ts,u: u,a: _a,color: color,colors: _colors,tags: _tags,ownerId: ownerId,opt: _opt,);
    return _dataConnect.mutation("CreateEverything", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class CreateEverythingEverythingInsert {
  final String id;
  CreateEverythingEverythingInsert.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateEverythingEverythingInsert otherTyped = other as CreateEverythingEverythingInsert;
    return id == otherTyped.id;
    
  }
  @override
  int get hashCode => id.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    return json;
  }

  CreateEverythingEverythingInsert({
    required this.id,
  });
}

@immutable
class CreateEverythingData {
  final CreateEverythingEverythingInsert everything_insert;
  CreateEverythingData.fromJson(dynamic json):
  
  everything_insert = CreateEverythingEverythingInsert.fromJson(json['everything_insert']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateEverythingData otherTyped = other as CreateEverythingData;
    return everything_insert == otherTyped.everything_insert;
    
  }
  @override
  int get hashCode => everything_insert.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['everything_insert'] = everything_insert.toJson();
    return json;
  }

  CreateEverythingData({
    required this.everything_insert,
  });
}

@immutable
class CreateEverythingVariables {
  final String s;
  final int i;
  final double f;
  final bool b;
  final BigInt i64;
  final DateTime d;
  final Timestamp ts;
  final String u;
  late final Optional<AnyValue>a;
  final Color color;
  late final Optional<List<Color>>colors;
  late final Optional<List<String>>tags;
  final String ownerId;
  late final Optional<String>opt;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  CreateEverythingVariables.fromJson(Map<String, dynamic> json):
  
  s = nativeFromJson<String>(json['s']),
  i = nativeFromJson<int>(json['i']),
  f = nativeFromJson<double>(json['f']),
  b = nativeFromJson<bool>(json['b']),
  i64 = bigIntFromJson(json['i64']),
  d = nativeFromJson<DateTime>(json['d']),
  ts = Timestamp.fromJson(json['ts']),
  u = nativeFromJson<String>(json['u']),
  color = Color.values.byName(json['color']),
  ownerId = nativeFromJson<String>(json['ownerId']) {
  
  
  
  
  
  
  
  
  
  
    a = Optional.optional(AnyValue.fromJson, defaultSerializer);
    a.value = json['a'] == null ? null : AnyValue.fromJson(json['a']);
  
  
  
    colors = Optional.optional(listDeserializer((data) => Color.values.byName(data)), listSerializer(enumSerializer));
    colors.value = json['colors'] == null ? null : (json['colors'] as List<dynamic>)
        .map((e) => Color.values.byName(e))
        .toList();
  
  
    tags = Optional.optional(listDeserializer(nativeFromJson), listSerializer(nativeToJson));
    tags.value = json['tags'] == null ? null : (json['tags'] as List<dynamic>)
        .map((e) => nativeFromJson<String>(e))
        .toList();
  
  
  
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

    final CreateEverythingVariables otherTyped = other as CreateEverythingVariables;
    return s == otherTyped.s && 
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
    ownerId == otherTyped.ownerId && 
    opt == otherTyped.opt;
    
  }
  @override
  int get hashCode => Object.hashAll([s.hashCode, i.hashCode, f.hashCode, b.hashCode, i64.hashCode, d.hashCode, ts.hashCode, u.hashCode, a.hashCode, color.hashCode, colors.hashCode, tags.hashCode, ownerId.hashCode, opt.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['s'] = nativeToJson<String>(s);
    json['i'] = nativeToJson<int>(i);
    json['f'] = nativeToJson<double>(f);
    json['b'] = nativeToJson<bool>(b);
    json['i64'] = bigIntToJson(i64);
    json['d'] = nativeToJson<DateTime>(d);
    json['ts'] = ts.toJson();
    json['u'] = nativeToJson<String>(u);
    if(a.state == OptionalState.set) {
      json['a'] = a.toJson();
    }
    json['color'] = 
    color.name
    ;
    if(colors.state == OptionalState.set) {
      json['colors'] = colors.toJson();
    }
    if(tags.state == OptionalState.set) {
      json['tags'] = tags.toJson();
    }
    json['ownerId'] = nativeToJson<String>(ownerId);
    if(opt.state == OptionalState.set) {
      json['opt'] = opt.toJson();
    }
    return json;
  }

  CreateEverythingVariables({
    required this.s,
    required this.i,
    required this.f,
    required this.b,
    required this.i64,
    required this.d,
    required this.ts,
    required this.u,
    required this.a,
    required this.color,
    required this.colors,
    required this.tags,
    required this.ownerId,
    required this.opt,
  });
}

