// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

/// Immutable class representing a GeoPoint in Firestore
class GeoPoint implements Comparable<GeoPoint> {
  /// Construct a new GeoPoint using the provided latitude and longitude values.
  ///
  /// The [latitude] of this GeoPoint in the range -90 to 90 and the [longitude] of this GeoPoint in
  /// the range -180 to 180.
  // NaN is detected with `x != x`, because `identical(x, double.nan)` never
  // matches a computed NaN (and `isNaN` is not usable in constant expressions).
  const GeoPoint(this.latitude, this.longitude)
    : assert(latitude == latitude, 'Latitude should not be a NaN.'),
      assert(
        latitude != double.infinity && latitude != double.negativeInfinity,
        'Latitude should not be an infinity.',
      ),
      assert(longitude == longitude, 'Longitude should not be a NaN.'),
      assert(
        longitude != double.infinity && longitude != double.negativeInfinity,
        'Longitude should not be an infinity.',
      ),
      assert(
        latitude >= -90.0 && latitude <= 90.0,
        'Latitude must be in the range of [-90, 90] but was $latitude',
      ),
      assert(
        longitude >= -180.0 && longitude <= 180.0,
        'Longitude must be in the range of [-180, 180] but was $longitude',
      );

  /// Builds a GeoPoint from a JSON map created by [toJson].
  ///
  /// Throws an [ArgumentError] if [json] does not have that shape or the
  /// coordinates are out of range.
  factory GeoPoint.fromJson(Map<String, Object?> json) {
    final Object? latitude = json['latitude'];
    final Object? longitude = json['longitude'];
    if (json['type'] != jsonType || latitude is! num || longitude is! num) {
      throw ArgumentError.value(
        json,
        'json',
        'Not a JSON representation of a GeoPoint',
      );
    }
    if (!(latitude >= -90 && latitude <= 90)) {
      throw RangeError.range(latitude, -90, 90, 'latitude');
    }
    if (!(longitude >= -180 && longitude <= 180)) {
      throw RangeError.range(longitude, -180, 180, 'longitude');
    }
    return GeoPoint(latitude.toDouble(), longitude.toDouble());
  }

  /// The value of the `type` field written by [toJson].
  static const String jsonType = 'firestore/geoPoint/1.0';

  /// The latitude, in degrees, between -90 and 90 inclusive.
  final double latitude;

  /// The longitude, in degrees, between -180 and 180 inclusive.
  final double longitude;

  /// A JSON-serializable representation of this GeoPoint, in the same shape as
  /// the JS SDK's `GeoPoint.toJSON()`. Read it back with [GeoPoint.fromJson].
  Map<String, Object> toJson() {
    return <String, Object>{
      'latitude': latitude,
      'longitude': longitude,
      'type': jsonType,
    };
  }

  @override
  int compareTo(GeoPoint other) {
    final int comparision = _compareCoordinates(latitude, other.latitude);
    if (comparision == 0) {
      return _compareCoordinates(longitude, other.longitude);
    } else {
      return comparision;
    }
  }

  /// Compares doubles like Firestore (the Android `NumberComparisonHelper.firestoreCompareDoubles`): 0.0 and -0.0 are
  /// equal, as for [==]; [double.compareTo] puts -0.0 first. NaN sorts first and equals itself.
  static int _compareCoordinates(double left, double right) {
    if (left < right) {
      return -1;
    } else if (left > right) {
      return 1;
    } else if (left == right) {
      return 0;
    }
    return left.isNaN ? (right.isNaN ? 0 : -1) : 1;
  }

  @override
  String toString() {
    return 'GeoPoint { latitude=$latitude, longitude=$longitude }';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode * 31 ^ longitude.hashCode * 31;
}
