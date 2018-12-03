///
//  Generated code. Do not modify.
//  source: google/firestore/v1beta1/query.proto
///
// ignore_for_file: non_constant_identifier_names,library_prefixes,unused_import

// ignore: UNUSED_SHOWN_NAME
import 'dart:core' show int, bool, double, String, List, override;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../protobuf/wrappers.pb.dart' as $0;
import 'document.pb.dart' as $1;

import 'query.pbenum.dart';

export 'query.pbenum.dart';

class StructuredQuery_CollectionSelector extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('StructuredQuery.CollectionSelector', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(2, 'collectionId')
    ..aOB(3, 'allDescendants')
    ..hasRequiredFields = false
  ;

  StructuredQuery_CollectionSelector() : super();
  StructuredQuery_CollectionSelector.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  StructuredQuery_CollectionSelector.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  StructuredQuery_CollectionSelector clone() => new StructuredQuery_CollectionSelector()..mergeFromMessage(this);
  StructuredQuery_CollectionSelector copyWith(void Function(StructuredQuery_CollectionSelector) updates) => super.copyWith((message) => updates(message as StructuredQuery_CollectionSelector));
  $pb.BuilderInfo get info_ => _i;
  static StructuredQuery_CollectionSelector create() => new StructuredQuery_CollectionSelector();
  static $pb.PbList<StructuredQuery_CollectionSelector> createRepeated() => new $pb.PbList<StructuredQuery_CollectionSelector>();
  static StructuredQuery_CollectionSelector getDefault() => _defaultInstance ??= create()..freeze();
  static StructuredQuery_CollectionSelector _defaultInstance;
  static void $checkItem(StructuredQuery_CollectionSelector v) {
    if (v is! StructuredQuery_CollectionSelector) $pb.checkItemFailed(v, _i.messageName);
  }

  String get collectionId => $_getS(0, '');
  set collectionId(String v) { $_setString(0, v); }
  bool hasCollectionId() => $_has(0);
  void clearCollectionId() => clearField(2);

  bool get allDescendants => $_get(1, false);
  set allDescendants(bool v) { $_setBool(1, v); }
  bool hasAllDescendants() => $_has(1);
  void clearAllDescendants() => clearField(3);
}

class StructuredQuery_Filter extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('StructuredQuery.Filter', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<StructuredQuery_CompositeFilter>(1, 'compositeFilter', $pb.PbFieldType.OM, StructuredQuery_CompositeFilter.getDefault, StructuredQuery_CompositeFilter.create)
    ..a<StructuredQuery_FieldFilter>(2, 'fieldFilter', $pb.PbFieldType.OM, StructuredQuery_FieldFilter.getDefault, StructuredQuery_FieldFilter.create)
    ..a<StructuredQuery_UnaryFilter>(3, 'unaryFilter', $pb.PbFieldType.OM, StructuredQuery_UnaryFilter.getDefault, StructuredQuery_UnaryFilter.create)
    ..hasRequiredFields = false
  ;

  StructuredQuery_Filter() : super();
  StructuredQuery_Filter.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  StructuredQuery_Filter.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  StructuredQuery_Filter clone() => new StructuredQuery_Filter()..mergeFromMessage(this);
  StructuredQuery_Filter copyWith(void Function(StructuredQuery_Filter) updates) => super.copyWith((message) => updates(message as StructuredQuery_Filter));
  $pb.BuilderInfo get info_ => _i;
  static StructuredQuery_Filter create() => new StructuredQuery_Filter();
  static $pb.PbList<StructuredQuery_Filter> createRepeated() => new $pb.PbList<StructuredQuery_Filter>();
  static StructuredQuery_Filter getDefault() => _defaultInstance ??= create()..freeze();
  static StructuredQuery_Filter _defaultInstance;
  static void $checkItem(StructuredQuery_Filter v) {
    if (v is! StructuredQuery_Filter) $pb.checkItemFailed(v, _i.messageName);
  }

  StructuredQuery_CompositeFilter get compositeFilter => $_getN(0);
  set compositeFilter(StructuredQuery_CompositeFilter v) { setField(1, v); }
  bool hasCompositeFilter() => $_has(0);
  void clearCompositeFilter() => clearField(1);

  StructuredQuery_FieldFilter get fieldFilter => $_getN(1);
  set fieldFilter(StructuredQuery_FieldFilter v) { setField(2, v); }
  bool hasFieldFilter() => $_has(1);
  void clearFieldFilter() => clearField(2);

  StructuredQuery_UnaryFilter get unaryFilter => $_getN(2);
  set unaryFilter(StructuredQuery_UnaryFilter v) { setField(3, v); }
  bool hasUnaryFilter() => $_has(2);
  void clearUnaryFilter() => clearField(3);
}

class StructuredQuery_CompositeFilter extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('StructuredQuery.CompositeFilter', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..e<StructuredQuery_CompositeFilter_Operator>(1, 'op', $pb.PbFieldType.OE, StructuredQuery_CompositeFilter_Operator.OPERATOR_UNSPECIFIED, StructuredQuery_CompositeFilter_Operator.valueOf, StructuredQuery_CompositeFilter_Operator.values)
    ..pp<StructuredQuery_Filter>(2, 'filters', $pb.PbFieldType.PM, StructuredQuery_Filter.$checkItem, StructuredQuery_Filter.create)
    ..hasRequiredFields = false
  ;

  StructuredQuery_CompositeFilter() : super();
  StructuredQuery_CompositeFilter.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  StructuredQuery_CompositeFilter.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  StructuredQuery_CompositeFilter clone() => new StructuredQuery_CompositeFilter()..mergeFromMessage(this);
  StructuredQuery_CompositeFilter copyWith(void Function(StructuredQuery_CompositeFilter) updates) => super.copyWith((message) => updates(message as StructuredQuery_CompositeFilter));
  $pb.BuilderInfo get info_ => _i;
  static StructuredQuery_CompositeFilter create() => new StructuredQuery_CompositeFilter();
  static $pb.PbList<StructuredQuery_CompositeFilter> createRepeated() => new $pb.PbList<StructuredQuery_CompositeFilter>();
  static StructuredQuery_CompositeFilter getDefault() => _defaultInstance ??= create()..freeze();
  static StructuredQuery_CompositeFilter _defaultInstance;
  static void $checkItem(StructuredQuery_CompositeFilter v) {
    if (v is! StructuredQuery_CompositeFilter) $pb.checkItemFailed(v, _i.messageName);
  }

  StructuredQuery_CompositeFilter_Operator get op => $_getN(0);
  set op(StructuredQuery_CompositeFilter_Operator v) { setField(1, v); }
  bool hasOp() => $_has(0);
  void clearOp() => clearField(1);

  List<StructuredQuery_Filter> get filters => $_getList(1);
}

class StructuredQuery_FieldFilter extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('StructuredQuery.FieldFilter', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<StructuredQuery_FieldReference>(1, 'field_1', $pb.PbFieldType.OM, StructuredQuery_FieldReference.getDefault, StructuredQuery_FieldReference.create)
    ..e<StructuredQuery_FieldFilter_Operator>(2, 'op', $pb.PbFieldType.OE, StructuredQuery_FieldFilter_Operator.OPERATOR_UNSPECIFIED, StructuredQuery_FieldFilter_Operator.valueOf, StructuredQuery_FieldFilter_Operator.values)
    ..a<$1.Value>(3, 'value', $pb.PbFieldType.OM, $1.Value.getDefault, $1.Value.create)
    ..hasRequiredFields = false
  ;

  StructuredQuery_FieldFilter() : super();
  StructuredQuery_FieldFilter.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  StructuredQuery_FieldFilter.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  StructuredQuery_FieldFilter clone() => new StructuredQuery_FieldFilter()..mergeFromMessage(this);
  StructuredQuery_FieldFilter copyWith(void Function(StructuredQuery_FieldFilter) updates) => super.copyWith((message) => updates(message as StructuredQuery_FieldFilter));
  $pb.BuilderInfo get info_ => _i;
  static StructuredQuery_FieldFilter create() => new StructuredQuery_FieldFilter();
  static $pb.PbList<StructuredQuery_FieldFilter> createRepeated() => new $pb.PbList<StructuredQuery_FieldFilter>();
  static StructuredQuery_FieldFilter getDefault() => _defaultInstance ??= create()..freeze();
  static StructuredQuery_FieldFilter _defaultInstance;
  static void $checkItem(StructuredQuery_FieldFilter v) {
    if (v is! StructuredQuery_FieldFilter) $pb.checkItemFailed(v, _i.messageName);
  }

  StructuredQuery_FieldReference get field_1 => $_getN(0);
  set field_1(StructuredQuery_FieldReference v) { setField(1, v); }
  bool hasField_1() => $_has(0);
  void clearField_1() => clearField(1);

  StructuredQuery_FieldFilter_Operator get op => $_getN(1);
  set op(StructuredQuery_FieldFilter_Operator v) { setField(2, v); }
  bool hasOp() => $_has(1);
  void clearOp() => clearField(2);

  $1.Value get value => $_getN(2);
  set value($1.Value v) { setField(3, v); }
  bool hasValue() => $_has(2);
  void clearValue() => clearField(3);
}

class StructuredQuery_UnaryFilter extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('StructuredQuery.UnaryFilter', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..e<StructuredQuery_UnaryFilter_Operator>(1, 'op', $pb.PbFieldType.OE, StructuredQuery_UnaryFilter_Operator.OPERATOR_UNSPECIFIED, StructuredQuery_UnaryFilter_Operator.valueOf, StructuredQuery_UnaryFilter_Operator.values)
    ..a<StructuredQuery_FieldReference>(2, 'field_2', $pb.PbFieldType.OM, StructuredQuery_FieldReference.getDefault, StructuredQuery_FieldReference.create)
    ..hasRequiredFields = false
  ;

  StructuredQuery_UnaryFilter() : super();
  StructuredQuery_UnaryFilter.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  StructuredQuery_UnaryFilter.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  StructuredQuery_UnaryFilter clone() => new StructuredQuery_UnaryFilter()..mergeFromMessage(this);
  StructuredQuery_UnaryFilter copyWith(void Function(StructuredQuery_UnaryFilter) updates) => super.copyWith((message) => updates(message as StructuredQuery_UnaryFilter));
  $pb.BuilderInfo get info_ => _i;
  static StructuredQuery_UnaryFilter create() => new StructuredQuery_UnaryFilter();
  static $pb.PbList<StructuredQuery_UnaryFilter> createRepeated() => new $pb.PbList<StructuredQuery_UnaryFilter>();
  static StructuredQuery_UnaryFilter getDefault() => _defaultInstance ??= create()..freeze();
  static StructuredQuery_UnaryFilter _defaultInstance;
  static void $checkItem(StructuredQuery_UnaryFilter v) {
    if (v is! StructuredQuery_UnaryFilter) $pb.checkItemFailed(v, _i.messageName);
  }

  StructuredQuery_UnaryFilter_Operator get op => $_getN(0);
  set op(StructuredQuery_UnaryFilter_Operator v) { setField(1, v); }
  bool hasOp() => $_has(0);
  void clearOp() => clearField(1);

  StructuredQuery_FieldReference get field_2 => $_getN(1);
  set field_2(StructuredQuery_FieldReference v) { setField(2, v); }
  bool hasField_2() => $_has(1);
  void clearField_2() => clearField(2);
}

class StructuredQuery_Order extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('StructuredQuery.Order', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<StructuredQuery_FieldReference>(1, 'field_1', $pb.PbFieldType.OM, StructuredQuery_FieldReference.getDefault, StructuredQuery_FieldReference.create)
    ..e<StructuredQuery_Direction>(2, 'direction', $pb.PbFieldType.OE, StructuredQuery_Direction.DIRECTION_UNSPECIFIED, StructuredQuery_Direction.valueOf, StructuredQuery_Direction.values)
    ..hasRequiredFields = false
  ;

  StructuredQuery_Order() : super();
  StructuredQuery_Order.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  StructuredQuery_Order.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  StructuredQuery_Order clone() => new StructuredQuery_Order()..mergeFromMessage(this);
  StructuredQuery_Order copyWith(void Function(StructuredQuery_Order) updates) => super.copyWith((message) => updates(message as StructuredQuery_Order));
  $pb.BuilderInfo get info_ => _i;
  static StructuredQuery_Order create() => new StructuredQuery_Order();
  static $pb.PbList<StructuredQuery_Order> createRepeated() => new $pb.PbList<StructuredQuery_Order>();
  static StructuredQuery_Order getDefault() => _defaultInstance ??= create()..freeze();
  static StructuredQuery_Order _defaultInstance;
  static void $checkItem(StructuredQuery_Order v) {
    if (v is! StructuredQuery_Order) $pb.checkItemFailed(v, _i.messageName);
  }

  StructuredQuery_FieldReference get field_1 => $_getN(0);
  set field_1(StructuredQuery_FieldReference v) { setField(1, v); }
  bool hasField_1() => $_has(0);
  void clearField_1() => clearField(1);

  StructuredQuery_Direction get direction => $_getN(1);
  set direction(StructuredQuery_Direction v) { setField(2, v); }
  bool hasDirection() => $_has(1);
  void clearDirection() => clearField(2);
}

class StructuredQuery_FieldReference extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('StructuredQuery.FieldReference', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(2, 'fieldPath')
    ..hasRequiredFields = false
  ;

  StructuredQuery_FieldReference() : super();
  StructuredQuery_FieldReference.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  StructuredQuery_FieldReference.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  StructuredQuery_FieldReference clone() => new StructuredQuery_FieldReference()..mergeFromMessage(this);
  StructuredQuery_FieldReference copyWith(void Function(StructuredQuery_FieldReference) updates) => super.copyWith((message) => updates(message as StructuredQuery_FieldReference));
  $pb.BuilderInfo get info_ => _i;
  static StructuredQuery_FieldReference create() => new StructuredQuery_FieldReference();
  static $pb.PbList<StructuredQuery_FieldReference> createRepeated() => new $pb.PbList<StructuredQuery_FieldReference>();
  static StructuredQuery_FieldReference getDefault() => _defaultInstance ??= create()..freeze();
  static StructuredQuery_FieldReference _defaultInstance;
  static void $checkItem(StructuredQuery_FieldReference v) {
    if (v is! StructuredQuery_FieldReference) $pb.checkItemFailed(v, _i.messageName);
  }

  String get fieldPath => $_getS(0, '');
  set fieldPath(String v) { $_setString(0, v); }
  bool hasFieldPath() => $_has(0);
  void clearFieldPath() => clearField(2);
}

class StructuredQuery_Projection extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('StructuredQuery.Projection', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..pp<StructuredQuery_FieldReference>(2, 'fields', $pb.PbFieldType.PM, StructuredQuery_FieldReference.$checkItem, StructuredQuery_FieldReference.create)
    ..hasRequiredFields = false
  ;

  StructuredQuery_Projection() : super();
  StructuredQuery_Projection.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  StructuredQuery_Projection.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  StructuredQuery_Projection clone() => new StructuredQuery_Projection()..mergeFromMessage(this);
  StructuredQuery_Projection copyWith(void Function(StructuredQuery_Projection) updates) => super.copyWith((message) => updates(message as StructuredQuery_Projection));
  $pb.BuilderInfo get info_ => _i;
  static StructuredQuery_Projection create() => new StructuredQuery_Projection();
  static $pb.PbList<StructuredQuery_Projection> createRepeated() => new $pb.PbList<StructuredQuery_Projection>();
  static StructuredQuery_Projection getDefault() => _defaultInstance ??= create()..freeze();
  static StructuredQuery_Projection _defaultInstance;
  static void $checkItem(StructuredQuery_Projection v) {
    if (v is! StructuredQuery_Projection) $pb.checkItemFailed(v, _i.messageName);
  }

  List<StructuredQuery_FieldReference> get fields => $_getList(0);
}

class StructuredQuery extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('StructuredQuery', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<StructuredQuery_Projection>(1, 'select', $pb.PbFieldType.OM, StructuredQuery_Projection.getDefault, StructuredQuery_Projection.create)
    ..pp<StructuredQuery_CollectionSelector>(2, 'from', $pb.PbFieldType.PM, StructuredQuery_CollectionSelector.$checkItem, StructuredQuery_CollectionSelector.create)
    ..a<StructuredQuery_Filter>(3, 'where', $pb.PbFieldType.OM, StructuredQuery_Filter.getDefault, StructuredQuery_Filter.create)
    ..pp<StructuredQuery_Order>(4, 'orderBy', $pb.PbFieldType.PM, StructuredQuery_Order.$checkItem, StructuredQuery_Order.create)
    ..a<$0.Int32Value>(5, 'limit', $pb.PbFieldType.OM, $0.Int32Value.getDefault, $0.Int32Value.create)
    ..a<int>(6, 'offset', $pb.PbFieldType.O3)
    ..a<Cursor>(7, 'startAt', $pb.PbFieldType.OM, Cursor.getDefault, Cursor.create)
    ..a<Cursor>(8, 'endAt', $pb.PbFieldType.OM, Cursor.getDefault, Cursor.create)
    ..hasRequiredFields = false
  ;

  StructuredQuery() : super();
  StructuredQuery.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  StructuredQuery.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  StructuredQuery clone() => new StructuredQuery()..mergeFromMessage(this);
  StructuredQuery copyWith(void Function(StructuredQuery) updates) => super.copyWith((message) => updates(message as StructuredQuery));
  $pb.BuilderInfo get info_ => _i;
  static StructuredQuery create() => new StructuredQuery();
  static $pb.PbList<StructuredQuery> createRepeated() => new $pb.PbList<StructuredQuery>();
  static StructuredQuery getDefault() => _defaultInstance ??= create()..freeze();
  static StructuredQuery _defaultInstance;
  static void $checkItem(StructuredQuery v) {
    if (v is! StructuredQuery) $pb.checkItemFailed(v, _i.messageName);
  }

  StructuredQuery_Projection get select => $_getN(0);
  set select(StructuredQuery_Projection v) { setField(1, v); }
  bool hasSelect() => $_has(0);
  void clearSelect() => clearField(1);

  List<StructuredQuery_CollectionSelector> get from => $_getList(1);

  StructuredQuery_Filter get where => $_getN(2);
  set where(StructuredQuery_Filter v) { setField(3, v); }
  bool hasWhere() => $_has(2);
  void clearWhere() => clearField(3);

  List<StructuredQuery_Order> get orderBy => $_getList(3);

  $0.Int32Value get limit => $_getN(4);
  set limit($0.Int32Value v) { setField(5, v); }
  bool hasLimit() => $_has(4);
  void clearLimit() => clearField(5);

  int get offset => $_get(5, 0);
  set offset(int v) { $_setSignedInt32(5, v); }
  bool hasOffset() => $_has(5);
  void clearOffset() => clearField(6);

  Cursor get startAt => $_getN(6);
  set startAt(Cursor v) { setField(7, v); }
  bool hasStartAt() => $_has(6);
  void clearStartAt() => clearField(7);

  Cursor get endAt => $_getN(7);
  set endAt(Cursor v) { setField(8, v); }
  bool hasEndAt() => $_has(7);
  void clearEndAt() => clearField(8);
}

class Cursor extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('Cursor', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..pp<$1.Value>(1, 'values', $pb.PbFieldType.PM, $1.Value.$checkItem, $1.Value.create)
    ..aOB(2, 'before')
    ..hasRequiredFields = false
  ;

  Cursor() : super();
  Cursor.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  Cursor.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  Cursor clone() => new Cursor()..mergeFromMessage(this);
  Cursor copyWith(void Function(Cursor) updates) => super.copyWith((message) => updates(message as Cursor));
  $pb.BuilderInfo get info_ => _i;
  static Cursor create() => new Cursor();
  static $pb.PbList<Cursor> createRepeated() => new $pb.PbList<Cursor>();
  static Cursor getDefault() => _defaultInstance ??= create()..freeze();
  static Cursor _defaultInstance;
  static void $checkItem(Cursor v) {
    if (v is! Cursor) $pb.checkItemFailed(v, _i.messageName);
  }

  List<$1.Value> get values => $_getList(0);

  bool get before => $_get(1, false);
  set before(bool v) { $_setBool(1, v); }
  bool hasBefore() => $_has(1);
  void clearBefore() => clearField(2);
}

