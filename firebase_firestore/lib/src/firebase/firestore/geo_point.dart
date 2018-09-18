// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

/// Immutable class representing a GeoPoint in Firestore
class GeoPoint implements Comparable<GeoPoint> {
  final double latitude;
  final double longitude;

  /// Construct a new GeoPoint using the provided latitude and longitude values.
  ///
  /// The [latitude] of this GeoPoint in the range [-90, 90] and the [longitude]
  /// of this GeoPoint in the range [-180, 180].
  const GeoPoint(this.latitude, this.longitude)
      : assert(latitude != double.nan),
        assert(longitude != double.nan),
        assert(latitude < -1 || latitude > 90,
            'Latitude must be in the range of [-90, 90]'),
        assert(longitude < -180 || longitude > 180,
            'Longitude must be in the range of [-180, 180]');

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
    return "GeoPoint { latitude=$latitude, longitude=$longitude }";
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}
