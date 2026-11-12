// The proto3 JSON the web transport sends: values that `toProto3Json()` of
// package:protobuf does not write faithfully.

import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/proto3_json.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:cloud_firestore_dart/src/proto/google/type/latlng.pb.dart'
    as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

typedef Json = Map<String, Object?>;

proto.Value doubleValue(double v) => proto.Value()..doubleValue = v;
proto.Value bytesValue(List<int> v) => proto.Value()..bytesValue = v;

/// Encodes like the transport and decodes like the backend would (and like
/// the transport decodes responses).
T roundTrip<T extends proto.Value>(proto.Value value) =>
    (proto.Value()
          ..mergeFromProto3Json(jsonDecode(jsonEncode(toFirestoreProto3Json(value)))))
        as T;

void main() {
  test('what toProto3Json alone gets wrong (the reason for this encoder)', () {
    // If these stop failing, package:protobuf was fixed and the encoder can go.
    expect(jsonEncode(doubleValue(-0.0).toProto3Json()),
        isNot(anyOf(contains('-0'), contains('"-0"'))));
    expect(bytesValue(<int>[]).toProto3Json(), isNot(containsPair('bytesValue', '')));
  });

  test('a negative zero is written as "-0", like the JS SDK', () {
    expect(toFirestoreProto3Json(doubleValue(-0.0)),
        <String, Object?>{'doubleValue': '-0'});
    expect(toFirestoreProto3Json(doubleValue(0.0)),
        <String, Object?>{'doubleValue': 0.0});
    final proto.Value back = roundTrip(doubleValue(-0.0));
    expect(back.doubleValue, 0.0);
    expect(back.doubleValue.isNegative, isTrue);
  });

  test('NaN and the infinities are written by name', () {
    expect(toFirestoreProto3Json(doubleValue(double.nan)),
        <String, Object?>{'doubleValue': 'NaN'});
    expect(toFirestoreProto3Json(doubleValue(double.infinity)),
        <String, Object?>{'doubleValue': 'Infinity'});
    expect(toFirestoreProto3Json(doubleValue(double.negativeInfinity)),
        <String, Object?>{'doubleValue': '-Infinity'});
    expect(roundTrip(doubleValue(double.nan)).doubleValue.isNaN, isTrue);
    expect(roundTrip(doubleValue(double.negativeInfinity)).doubleValue,
        double.negativeInfinity);
  });

  test('an empty bytes value keeps its type', () {
    expect(toFirestoreProto3Json(bytesValue(<int>[])),
        <String, Object?>{'bytesValue': ''});
    final proto.Value back = roundTrip(bytesValue(<int>[]));
    expect(back.whichValueType(), proto.Value_ValueType.bytesValue);
    expect(back.bytesValue, isEmpty);
    expect(toFirestoreProto3Json(bytesValue(<int>[0, 255])),
        <String, Object?>{'bytesValue': 'AP8='});
  });

  test('the bounds of 64 bit integers are written as strings', () {
    for (final Int64 bound in <Int64>[Int64.MAX_VALUE, Int64.MIN_VALUE]) {
      final proto.Value value = proto.Value()..integerValue = bound;
      expect(toFirestoreProto3Json(value),
          <String, Object?>{'integerValue': bound.toString()});
      expect(roundTrip(value).integerValue, bound);
    }
  });

  test('a GeoPoint keeps the sign of its zeros', () {
    final proto.Value value = proto.Value()
      ..geoPointValue = (proto.LatLng()
        ..latitude = -0.0
        ..longitude = 1.5);
    expect(toFirestoreProto3Json(value), <String, Object?>{
      'geoPointValue': <String, Object?>{'latitude': '-0', 'longitude': 1.5},
    });
    expect(roundTrip(value).geoPointValue.latitude.isNegative, isTrue);
  });

  test('values nested in arrays and maps are encoded the same way', () {
    final proto.Value value = proto.Value()
      ..mapValue = (proto.MapValue()
        ..fields['list'] = (proto.Value()
          ..arrayValue = (proto.ArrayValue()
            ..values.addAll(<proto.Value>[
              doubleValue(-0.0),
              bytesValue(<int>[]),
              proto.Value()..stringValue = 'x',
            ])))
        ..fields['empty'] = bytesValue(<int>[]));
    expect(toFirestoreProto3Json(value), <String, Object?>{
      'mapValue': <String, Object?>{
        'fields': <String, Object?>{
          'list': <String, Object?>{
            'arrayValue': <String, Object?>{
              'values': <Object?>[
                <String, Object?>{'doubleValue': '-0'},
                <String, Object?>{'bytesValue': ''},
                <String, Object?>{'stringValue': 'x'},
              ],
            },
          },
          'empty': <String, Object?>{'bytesValue': ''},
        },
      },
    });
    expect(roundTrip(value).writeToBuffer(), value.writeToBuffer());
  });

  test('the values of a write request: fields and transforms', () {
    final proto.WriteRequest request = proto.WriteRequest()
      ..database = 'projects/p/databases/(default)'
      ..writes.add(proto.Write()
        ..update = (proto.Document()
          ..name = 'projects/p/databases/(default)/documents/c/d'
          ..fields['zero'] = doubleValue(-0.0)
          ..fields['blob'] = bytesValue(<int>[]))
        ..updateTransforms.add(proto.DocumentTransform_FieldTransform()
          ..fieldPath = 'n'
          ..increment = doubleValue(-0.0))
        ..updateTransforms.add(proto.DocumentTransform_FieldTransform()
          ..fieldPath = 'list'
          ..appendMissingElements = (proto.ArrayValue()
            ..values.add(bytesValue(<int>[])))));

    final Json json = (toFirestoreProto3Json(request)! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final Json write = ((json['writes']! as List<Object?>).single! as Map<Object?, Object?>)
        .cast<String, Object?>();
    expect((write['update']! as Map<Object?, Object?>)['fields'], <String, Object?>{
      'zero': <String, Object?>{'doubleValue': '-0'},
      'blob': <String, Object?>{'bytesValue': ''},
    });
    expect(write['updateTransforms'], <Object?>[
      <String, Object?>{
        'fieldPath': 'n',
        'increment': <String, Object?>{'doubleValue': '-0'},
      },
      <String, Object?>{
        'fieldPath': 'list',
        'appendMissingElements': <String, Object?>{
          'values': <Object?>[
            <String, Object?>{'bytesValue': ''},
          ],
        },
      },
    ]);

    // The whole request survives the encoding.
    final proto.WriteRequest back = proto.WriteRequest()
      ..mergeFromProto3Json(jsonDecode(jsonEncode(json)));
    expect(back.writeToBuffer(), request.writeToBuffer());
  });

  test('the values of a query: filters and cursors', () {
    final proto.RunQueryRequest request = proto.RunQueryRequest()
      ..parent = 'projects/p/databases/(default)/documents'
      ..structuredQuery = (proto.StructuredQuery()
        ..from.add(proto.StructuredQuery_CollectionSelector()..collectionId = 'c')
        ..where = (proto.StructuredQuery_Filter()
          ..fieldFilter = (proto.StructuredQuery_FieldFilter()
            ..field_1 = (proto.StructuredQuery_FieldReference()..fieldPath = 'v')
            ..op = proto.StructuredQuery_FieldFilter_Operator.EQUAL
            ..value = bytesValue(<int>[])))
        ..startAt = (proto.Cursor()
          ..values.add(doubleValue(-0.0))
          ..before = true));

    final Object? json = toFirestoreProto3Json(request);
    final String text = jsonEncode(json);
    expect(text, contains('"value":{"bytesValue":""}'));
    expect(text, contains('"values":[{"doubleValue":"-0"}]'));
    final proto.RunQueryRequest back = proto.RunQueryRequest()
      ..mergeFromProto3Json(jsonDecode(text));
    expect(back.writeToBuffer(), request.writeToBuffer());
  });

  test('a response with a negative zero or an empty blob is read faithfully',
      () {
    // As the JSON endpoints of the emulator write them.
    final proto.Document document = proto.Document()
      ..mergeFromProto3Json(jsonDecode(
          '{"name":"n","fields":{"z":{"doubleValue":-0.0},"b":{"bytesValue":""},'
          '"g":{"geoPointValue":{"latitude":-0.0,"longitude":-0.0}}}}'));
    expect(document.fields['z']!.doubleValue.isNegative, isTrue);
    expect(document.fields['b']!.whichValueType(),
        proto.Value_ValueType.bytesValue);
    expect(document.fields['g']!.geoPointValue.latitude.isNegative, isTrue);
  });
}
