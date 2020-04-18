// Copyright 2017, the Chromium project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of cloud_firestore_dart_implementation;

/// Class containing static utility methods to encode/decode firestore data.
class CodecUtility {
  /// Encodes a Map of values from their proper types to a serialized version.
  static Map<String, dynamic> encodeMapData(Map<String, dynamic> data) {
    if (data == null) {
      return null;
    }
    return Map<String, dynamic>.from(data)
      ..updateAll((String key, dynamic value) => valueEncode(value));
  }

  /// Encodes an Array of values from their proper types to a serialized version.
  static List<dynamic> encodeArrayData(List<dynamic> data) {
    if (data == null) {
      return null;
    }
    return List<dynamic>.from(data).map<dynamic>(valueEncode).toList();
  }

  /// Encodes a value from its proper type to a serialized version.
  static dynamic valueEncode(dynamic value) {
    if (value is FieldValuePlatform) {
      final FieldValueDart delegate = FieldValuePlatform.getDelegate(value);
      return delegate.data;
    } else if (value is Timestamp) {
      return value.toDate();
    } else if (value is GeoPoint) {
      return dart.GeoPoint(value.latitude, value.longitude);
    } else if (value is Blob) {
      return dart.Blob(value.bytes);
    } else if (value is DocumentReferenceDart) {
      return value._delegate;
    } else if (value is Map<String, dynamic>) {
      return encodeMapData(value);
    } else if (value is List<dynamic>) {
      return encodeArrayData(value);
    }
    return value;
  }

  /// Decodes the values on an incoming Map to their proper types.
  static Map<String, dynamic> decodeMapData(Map<String, dynamic> data) {
    if (data == null) {
      return null;
    }
    return Map<String, dynamic>.from(data)
      ..updateAll((String key, dynamic value) => valueDecode(value));
  }

  /// Decodes the values on an incoming Array to their proper types.
  static List<dynamic> decodeArrayData(List<dynamic> data) {
    if (data == null) {
      return null;
    }
    return List<dynamic>.from(data).map<dynamic>(valueDecode).toList();
  }

  /// Decodes an incoming value to its proper type.
  static dynamic valueDecode(dynamic value) {
    if (value is dart.GeoPoint) {
      return GeoPoint(value.latitude, value.longitude);
    } else if (value is DateTime) {
      return Timestamp.fromDate(value);
    } else if (value is dart.Blob) {
      return Blob(value.bytes);
    } else if (value is dart.DocumentReference) {
      final FirestoreDart firestore = FirestorePlatform.instance;
      return firestore.document(value.path);
    } else if (value is Map<String, dynamic>) {
      return decodeMapData(value);
    } else if (value is List<dynamic>) {
      return decodeArrayData(value);
    }
    return value;
  }
}
