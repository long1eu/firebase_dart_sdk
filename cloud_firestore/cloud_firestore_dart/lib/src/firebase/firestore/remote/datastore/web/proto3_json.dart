// Proto3 JSON for the requests of the web transport.

import 'dart:convert';

import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:protobuf/protobuf.dart';

/// Encodes [message] as proto3 JSON, with the Firestore values in it encoded
/// the way the serializer of the JS SDK does.
///
/// PORTING NOTE: `GeneratedMessage.toProto3Json()` alone is not faithful for
/// values. It writes the double -0.0 as `0` (the sign is lost, also in a
/// `GeoPoint`) and an empty `bytesValue` as an empty object (the value loses
/// its type and the backend rejects or misreads it). The bundle builder has
/// the same workaround for the values of a bundle.
Object? toFirestoreProto3Json(GeneratedMessage message) {
  if (message is proto.Value) {
    return _encodeValue(message);
  }
  final Object? json = message.toProto3Json();
  _patch(message, json);
  return json;
}

/// Replaces the JSON of every value below [message] in [json], its encoding.
void _patch(GeneratedMessage message, Object? json) {
  if (json is! Map) {
    return;
  }
  for (final FieldInfo<dynamic> info in message.info_.fieldInfo.values) {
    final Object? field = message.getFieldOrNull(info.tagNumber);
    if (field == null) {
      continue;
    }
    final String key = info.name;
    if (field is proto.Value) {
      json[key] = _encodeValue(field);
    } else if (field is GeneratedMessage) {
      _patch(field, json[key]);
    } else if (field is Map) {
      final Object? encoded = json[key];
      if (encoded is Map) {
        field.forEach((Object? name, Object? element) {
          if (element is proto.Value) {
            encoded[name] = _encodeValue(element);
          } else if (element is GeneratedMessage) {
            _patch(element, encoded[name]);
          }
        });
      }
    } else if (field is List) {
      final Object? encoded = json[key];
      if (encoded is List && encoded.length == field.length) {
        for (int i = 0; i < field.length; i++) {
          final Object? element = field[i];
          if (element is proto.Value) {
            encoded[i] = _encodeValue(element);
          } else if (element is GeneratedMessage) {
            _patch(element, encoded[i]);
          }
        }
      }
    }
  }
}

Object _encodeDouble(double value) {
  if (value.isNaN) {
    return 'NaN';
  } else if (value.isInfinite) {
    return value.isNegative ? '-Infinity' : 'Infinity';
  } else if (value == 0 && value.isNegative) {
    // As the JS SDK: a JSON number would do, but an integral double is
    // printed without its sign by some encoders.
    return '-0';
  }
  return value;
}

Object? _encodeValue(proto.Value value) {
  // The oneof case, not hasXxx(): an empty bytes value 'has' no value.
  switch (value.whichValueType()) {
    case proto.Value_ValueType.doubleValue:
      return <String, Object?>{'doubleValue': _encodeDouble(value.doubleValue)};
    case proto.Value_ValueType.bytesValue:
      return <String, Object?>{'bytesValue': base64Encode(value.bytesValue)};
    case proto.Value_ValueType.geoPointValue:
      return <String, Object?>{
        'geoPointValue': <String, Object?>{
          'latitude': _encodeDouble(value.geoPointValue.latitude),
          'longitude': _encodeDouble(value.geoPointValue.longitude),
        },
      };
    case proto.Value_ValueType.arrayValue:
      return <String, Object?>{
        'arrayValue': <String, Object?>{
          'values': value.arrayValue.values.map(_encodeValue).toList(),
        },
      };
    case proto.Value_ValueType.mapValue:
      return <String, Object?>{
        'mapValue': <String, Object?>{
          'fields': <String, Object?>{
            for (final MapEntry<String, proto.Value> field
                in value.mapValue.fields.entries)
              field.key: _encodeValue(field.value),
          },
        },
      };
    // ignore: no_default_cases
    default:
      // The other types have no such quirk; values nested in them (the
      // arguments of a pipeline function, for example) are still patched.
      final Object? json = value.toProto3Json();
      _patch(value, json);
      return json;
  }
}
