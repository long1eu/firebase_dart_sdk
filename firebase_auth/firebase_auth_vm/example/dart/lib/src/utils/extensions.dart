// File created by
// Lung Razvan <long1eu>
// on 16/12/2019

extension MapExtension on Map<String, String> {
  List<String> get pairs {
    return keys
        .map((String key) => '$key=${Uri.encodeQueryComponent(this[key])}')
        .toList()
          ..sort();
  }

  List<String> pairsWhere(bool Function(String key) test) {
    return keys
        .where(test)
        .map((String key) => '$key=${Uri.encodeQueryComponent(this[key])}')
        .toList()
          ..sort();
  }
}

extension StringExtension on String {
  Map<String, String> get queryParameters {
    return split('&')
        .map((String value) => value.split('='))
        .toList()
        .asMap()
        .map((_, List<String> value) =>
            MapEntry<String, String>(value[0], value[1]));
  }
}
