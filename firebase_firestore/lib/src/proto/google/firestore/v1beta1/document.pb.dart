///
//  Generated code. Do not modify.
//  source: google/firestore/v1beta1/document.proto
///
// ignore_for_file: non_constant_identifier_names,library_prefixes,unused_import

// ignore: UNUSED_SHOWN_NAME
import 'dart:core' show int, bool, double, String, List, override;

import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart' as $pb;

import '../../protobuf/timestamp.pb.dart' as $0;
import '../../type/latlng.pb.dart' as $1;

import '../../protobuf/struct.pbenum.dart' as $2;

class Document_FieldsEntry extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('Document.FieldsEntry', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'key')
    ..a<Value>(2, 'value', $pb.PbFieldType.OM, Value.getDefault, Value.create)
    ..hasRequiredFields = false
  ;

  Document_FieldsEntry() : super();
  Document_FieldsEntry.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  Document_FieldsEntry.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  Document_FieldsEntry clone() => new Document_FieldsEntry()..mergeFromMessage(this);
  Document_FieldsEntry copyWith(void Function(Document_FieldsEntry) updates) => super.copyWith((message) => updates(message as Document_FieldsEntry));
  $pb.BuilderInfo get info_ => _i;
  static Document_FieldsEntry create() => new Document_FieldsEntry();
  static $pb.PbList<Document_FieldsEntry> createRepeated() => new $pb.PbList<Document_FieldsEntry>();
  static Document_FieldsEntry getDefault() => _defaultInstance ??= create()..freeze();
  static Document_FieldsEntry _defaultInstance;
  static void $checkItem(Document_FieldsEntry v) {
    if (v is! Document_FieldsEntry) $pb.checkItemFailed(v, _i.messageName);
  }

  String get key => $_getS(0, '');
  set key(String v) { $_setString(0, v); }
  bool hasKey() => $_has(0);
  void clearKey() => clearField(1);

  Value get value => $_getN(1);
  set value(Value v) { setField(2, v); }
  bool hasValue() => $_has(1);
  void clearValue() => clearField(2);
}

class Document extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('Document', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'name')
    ..pp<Document_FieldsEntry>(2, 'fields', $pb.PbFieldType.PM, Document_FieldsEntry.$checkItem, Document_FieldsEntry.create)
    ..a<$0.Timestamp>(3, 'createTime', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..a<$0.Timestamp>(4, 'updateTime', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..hasRequiredFields = false
  ;

  Document() : super();
  Document.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  Document.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  Document clone() => new Document()..mergeFromMessage(this);
  Document copyWith(void Function(Document) updates) => super.copyWith((message) => updates(message as Document));
  $pb.BuilderInfo get info_ => _i;
  static Document create() => new Document();
  static $pb.PbList<Document> createRepeated() => new $pb.PbList<Document>();
  static Document getDefault() => _defaultInstance ??= create()..freeze();
  static Document _defaultInstance;
  static void $checkItem(Document v) {
    if (v is! Document) $pb.checkItemFailed(v, _i.messageName);
  }

  String get name => $_getS(0, '');
  set name(String v) { $_setString(0, v); }
  bool hasName() => $_has(0);
  void clearName() => clearField(1);

  List<Document_FieldsEntry> get fields => $_getList(1);

  $0.Timestamp get createTime => $_getN(2);
  set createTime($0.Timestamp v) { setField(3, v); }
  bool hasCreateTime() => $_has(2);
  void clearCreateTime() => clearField(3);

  $0.Timestamp get updateTime => $_getN(3);
  set updateTime($0.Timestamp v) { setField(4, v); }
  bool hasUpdateTime() => $_has(3);
  void clearUpdateTime() => clearField(4);
}

class Value extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('Value', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOB(1, 'booleanValue')
    ..aInt64(2, 'integerValue')
    ..a<double>(3, 'doubleValue', $pb.PbFieldType.OD)
    ..aOS(5, 'referenceValue')
    ..a<MapValue>(6, 'mapValue', $pb.PbFieldType.OM, MapValue.getDefault, MapValue.create)
    ..a<$1.LatLng>(8, 'geoPointValue', $pb.PbFieldType.OM, $1.LatLng.getDefault, $1.LatLng.create)
    ..a<ArrayValue>(9, 'arrayValue', $pb.PbFieldType.OM, ArrayValue.getDefault, ArrayValue.create)
    ..a<$0.Timestamp>(10, 'timestampValue', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..e<$2.NullValue>(11, 'nullValue', $pb.PbFieldType.OE, $2.NullValue.NULL_VALUE, $2.NullValue.valueOf, $2.NullValue.values)
    ..aOS(17, 'stringValue')
    ..a<List<int>>(18, 'bytesValue', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  Value() : super();
  Value.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  Value.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  Value clone() => new Value()..mergeFromMessage(this);
  Value copyWith(void Function(Value) updates) => super.copyWith((message) => updates(message as Value));
  $pb.BuilderInfo get info_ => _i;
  static Value create() => new Value();
  static $pb.PbList<Value> createRepeated() => new $pb.PbList<Value>();
  static Value getDefault() => _defaultInstance ??= create()..freeze();
  static Value _defaultInstance;
  static void $checkItem(Value v) {
    if (v is! Value) $pb.checkItemFailed(v, _i.messageName);
  }

  bool get booleanValue => $_get(0, false);
  set booleanValue(bool v) { $_setBool(0, v); }
  bool hasBooleanValue() => $_has(0);
  void clearBooleanValue() => clearField(1);

  Int64 get integerValue => $_getI64(1);
  set integerValue(Int64 v) { $_setInt64(1, v); }
  bool hasIntegerValue() => $_has(1);
  void clearIntegerValue() => clearField(2);

  double get doubleValue => $_getN(2);
  set doubleValue(double v) { $_setDouble(2, v); }
  bool hasDoubleValue() => $_has(2);
  void clearDoubleValue() => clearField(3);

  String get referenceValue => $_getS(3, '');
  set referenceValue(String v) { $_setString(3, v); }
  bool hasReferenceValue() => $_has(3);
  void clearReferenceValue() => clearField(5);

  MapValue get mapValue => $_getN(4);
  set mapValue(MapValue v) { setField(6, v); }
  bool hasMapValue() => $_has(4);
  void clearMapValue() => clearField(6);

  $1.LatLng get geoPointValue => $_getN(5);
  set geoPointValue($1.LatLng v) { setField(8, v); }
  bool hasGeoPointValue() => $_has(5);
  void clearGeoPointValue() => clearField(8);

  ArrayValue get arrayValue => $_getN(6);
  set arrayValue(ArrayValue v) { setField(9, v); }
  bool hasArrayValue() => $_has(6);
  void clearArrayValue() => clearField(9);

  $0.Timestamp get timestampValue => $_getN(7);
  set timestampValue($0.Timestamp v) { setField(10, v); }
  bool hasTimestampValue() => $_has(7);
  void clearTimestampValue() => clearField(10);

  $2.NullValue get nullValue => $_getN(8);
  set nullValue($2.NullValue v) { setField(11, v); }
  bool hasNullValue() => $_has(8);
  void clearNullValue() => clearField(11);

  String get stringValue => $_getS(9, '');
  set stringValue(String v) { $_setString(9, v); }
  bool hasStringValue() => $_has(9);
  void clearStringValue() => clearField(17);

  List<int> get bytesValue => $_getN(10);
  set bytesValue(List<int> v) { $_setBytes(10, v); }
  bool hasBytesValue() => $_has(10);
  void clearBytesValue() => clearField(18);
}

class ArrayValue extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('ArrayValue', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..pp<Value>(1, 'values', $pb.PbFieldType.PM, Value.$checkItem, Value.create)
    ..hasRequiredFields = false
  ;

  ArrayValue() : super();
  ArrayValue.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  ArrayValue.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  ArrayValue clone() => new ArrayValue()..mergeFromMessage(this);
  ArrayValue copyWith(void Function(ArrayValue) updates) => super.copyWith((message) => updates(message as ArrayValue));
  $pb.BuilderInfo get info_ => _i;
  static ArrayValue create() => new ArrayValue();
  static $pb.PbList<ArrayValue> createRepeated() => new $pb.PbList<ArrayValue>();
  static ArrayValue getDefault() => _defaultInstance ??= create()..freeze();
  static ArrayValue _defaultInstance;
  static void $checkItem(ArrayValue v) {
    if (v is! ArrayValue) $pb.checkItemFailed(v, _i.messageName);
  }

  List<Value> get values => $_getList(0);
}

class MapValue_FieldsEntry extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('MapValue.FieldsEntry', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'key')
    ..a<Value>(2, 'value', $pb.PbFieldType.OM, Value.getDefault, Value.create)
    ..hasRequiredFields = false
  ;

  MapValue_FieldsEntry() : super();
  MapValue_FieldsEntry.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  MapValue_FieldsEntry.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  MapValue_FieldsEntry clone() => new MapValue_FieldsEntry()..mergeFromMessage(this);
  MapValue_FieldsEntry copyWith(void Function(MapValue_FieldsEntry) updates) => super.copyWith((message) => updates(message as MapValue_FieldsEntry));
  $pb.BuilderInfo get info_ => _i;
  static MapValue_FieldsEntry create() => new MapValue_FieldsEntry();
  static $pb.PbList<MapValue_FieldsEntry> createRepeated() => new $pb.PbList<MapValue_FieldsEntry>();
  static MapValue_FieldsEntry getDefault() => _defaultInstance ??= create()..freeze();
  static MapValue_FieldsEntry _defaultInstance;
  static void $checkItem(MapValue_FieldsEntry v) {
    if (v is! MapValue_FieldsEntry) $pb.checkItemFailed(v, _i.messageName);
  }

  String get key => $_getS(0, '');
  set key(String v) { $_setString(0, v); }
  bool hasKey() => $_has(0);
  void clearKey() => clearField(1);

  Value get value => $_getN(1);
  set value(Value v) { setField(2, v); }
  bool hasValue() => $_has(1);
  void clearValue() => clearField(2);
}

class MapValue extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('MapValue', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..pp<MapValue_FieldsEntry>(1, 'fields', $pb.PbFieldType.PM, MapValue_FieldsEntry.$checkItem, MapValue_FieldsEntry.create)
    ..hasRequiredFields = false
  ;

  MapValue() : super();
  MapValue.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  MapValue.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  MapValue clone() => new MapValue()..mergeFromMessage(this);
  MapValue copyWith(void Function(MapValue) updates) => super.copyWith((message) => updates(message as MapValue));
  $pb.BuilderInfo get info_ => _i;
  static MapValue create() => new MapValue();
  static $pb.PbList<MapValue> createRepeated() => new $pb.PbList<MapValue>();
  static MapValue getDefault() => _defaultInstance ??= create()..freeze();
  static MapValue _defaultInstance;
  static void $checkItem(MapValue v) {
    if (v is! MapValue) $pb.checkItemFailed(v, _i.messageName);
  }

  List<MapValue_FieldsEntry> get fields => $_getList(0);
}

