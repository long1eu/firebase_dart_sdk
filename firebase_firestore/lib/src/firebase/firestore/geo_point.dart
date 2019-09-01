// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

/// Immutable class representing a GeoPoint in Firestore
class GeoPoint implements Comparable<GeoPoint> {
  /// Construct a new GeoPoint using the provided latitude and longitude values.
  ///
  /// The [latitude] of this GeoPoint in the range [-90, 90] and the [longitude]
  /// of this GeoPoint in the range [-180, 180].
  const GeoPoint(this.latitude, this.longitude)
      : assert(
            !identical(latitude, double.nan), 'Latitude should not be a NaN.'),
        assert(
            latitude != double.infinity, 'Latitude should not be a infinity.'),
        assert(!identical(longitude, double.nan),
            'Longitude should not be a NaN.'),
        assert(longitude != double.negativeInfinity,
            'Longitude should not be a negativeInfinity.'),
        assert(latitude >= -90.0 && latitude <= 90.0,
            'Latitude must be in the range of [-90, 90] but was $latitude'),
        assert(longitude >= -180.0 && longitude <= 180.0,
            'Longitude must be in the range of [-180, 180] but was $longitude');

  final double latitude;
  final double longitude;

  @override
  int compareTo(GeoPoint other) {
    final int comparision = latitude.compareTo(other.latitude);
    if (comparision == 0) {
      return longitude.compareTo(other.longitude);
    } else {
      return comparision;
    }
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
