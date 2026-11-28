import 'dart:convert';

import 'exception.dart';
import 'limits.dart';

final RegExp _namePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

/// The largest integer that keeps its value on every platform: on the web, integers above 2^53 lose
/// precision.
const int _maxSafeInteger = 9007199254740991;

/// The length a limit counts for [value]: the length of its percent-encoded form, the stricter reading of
/// "the encoded URL character length is used when counting character limits" (protocol §4). An ASCII
/// letter or digit counts one; `é` counts six.
int measuredLength(String value) => Uri.encodeComponent(value).length;

FirebaseAnalyticsException _error(String code, String message) =>
    FirebaseAnalyticsException(code: code, message: message);

/// Checks an event name: its characters, its length, and the reserved names and prefixes.
void checkEventName(String name) {
  if (name.isEmpty ||
      name.length > AnalyticsLimits.maxEventNameLength ||
      !_namePattern.hasMatch(name)) {
    throw _error(
      'invalid-event-name',
      'Event name "${_shown(name)}" must be 1 to ${AnalyticsLimits.maxEventNameLength} letters, digits or '
          'underscores, starting with a letter.',
    );
  }
  if (reservedEventNames.contains(name)) {
    throw _error(
      'reserved-name',
      'Event name "$name" is reserved by the Measurement Protocol${name == 'screen_view' ? '; use logScreenView, which sends page_view' : ''}.',
    );
  }
  for (final String prefix in reservedEventPrefixes) {
    if (name.startsWith(prefix)) {
      throw _error(
        'reserved-name',
        'Event name "$name" starts with the reserved prefix "$prefix".',
      );
    }
  }
}

/// Checks the parameters of an event or the default parameters and returns them in the form they are sent:
/// null values dropped, `bool` as `1` or `0`, `items` as a list of maps.
Map<String, Object> normalizeParameters(Map<String, Object?> parameters) {
  final Map<String, Object> out = <String, Object>{};
  parameters.forEach((String name, Object? value) {
    _checkParameterName(name, what: 'Parameter');
    if (value == null) {
      return;
    }
    if (name == 'items') {
      out[name] = _normalizeItems(value);
    } else {
      out[name] = _normalizeValue(name, value);
    }
  });
  return out;
}

void _checkParameterName(String name, {required String what}) {
  if (name.isEmpty ||
      name.length > AnalyticsLimits.maxParameterNameLength ||
      !_namePattern.hasMatch(name)) {
    throw _error(
      'invalid-parameter',
      '$what name "${_shown(name)}" must be 1 to ${AnalyticsLimits.maxParameterNameLength} letters, digits or '
          'underscores, starting with a letter.',
    );
  }
  if (reservedParameterNames.contains(name)) {
    throw _error(
      'reserved-name',
      '$what name "$name" is reserved by the Measurement Protocol.',
    );
  }
  if (clientParameterNames.contains(name)) {
    throw _error(
      'reserved-name',
      '$what name "$name" is set by the client on every event.',
    );
  }
  for (final String prefix in reservedParameterPrefixes) {
    if (name.startsWith(prefix)) {
      throw _error(
        'reserved-name',
        '$what name "$name" starts with the reserved prefix "$prefix".',
      );
    }
  }
}

Object _normalizeValue(String name, Object value, {String what = 'Parameter'}) {
  if (value is String) {
    if (measuredLength(value) > AnalyticsLimits.maxParameterValueLength) {
      throw _error(
        'invalid-parameter',
        '$what "$name" is longer than ${AnalyticsLimits.maxParameterValueLength} characters, counted in its '
            'percent-encoded form.',
      );
    }
    return value;
  }
  if (value is bool) {
    return value ? 1 : 0;
  }
  if (value is num) {
    return checkNumber(name, value, what: what);
  }
  throw _error(
    'invalid-parameter',
    '$what "$name" is a ${value.runtimeType}; values are String, int, double or bool${what == 'Parameter' ? ', and items a list of maps' : ''}.',
  );
}

/// Checks a number for a parameter: finite, and an integer within the range every platform represents
/// exactly. Every number the client sends goes through here (design rule 9 of contributing_a_product.md).
num checkNumber(String name, num value, {String what = 'Parameter'}) {
  // First: compiled to JavaScript, an infinity passes `is int`.
  if (!value.isFinite) {
    throw _error('invalid-parameter', '$what "$name" is not a finite number.');
  }
  if (value is int && (value > _maxSafeInteger || value < -_maxSafeInteger)) {
    throw _error(
      'invalid-parameter',
      '$what "$name" is an integer beyond 2^53, which loses precision.',
    );
  }
  return value;
}

List<Map<String, Object>> _normalizeItems(Object value) {
  if (value is! List) {
    throw _error(
      'invalid-parameter',
      'Parameter "items" must be a list of maps.',
    );
  }
  final List<Map<String, Object>> items = <Map<String, Object>>[];
  for (int i = 0; i < value.length; i++) {
    final Object? item = value[i];
    if (item is! Map) {
      throw _error('invalid-parameter', 'Item $i of "items" is not a map.');
    }
    final Map<String, Object> out = <String, Object>{};
    int custom = 0;
    for (final MapEntry<Object?, Object?> entry in item.entries) {
      final Object? key = entry.key;
      if (key is! String) {
        throw _error(
          'invalid-parameter',
          'Item $i of "items" has a key that is not a String.',
        );
      }
      _checkParameterName(key, what: 'Item parameter');
      if (key == 'items') {
        throw _error(
          'invalid-parameter',
          'Item $i of "items" cannot have items of its own.',
        );
      }
      if (!documentedItemParameters.contains(key)) {
        custom++;
      }
      final Object? itemValue = entry.value;
      if (itemValue == null) {
        continue;
      }
      out[key] = _normalizeValue(key, itemValue, what: 'Item parameter');
    }
    if (custom > AnalyticsLimits.maxCustomItemParameters) {
      throw _error(
        'invalid-parameter',
        'Item $i of "items" has $custom custom parameters; at most '
            '${AnalyticsLimits.maxCustomItemParameters} are allowed.',
      );
    }
    if (!out.containsKey('item_id') && !out.containsKey('item_name')) {
      throw _error(
        'invalid-parameter',
        'Item $i of "items" needs an item_id or an item_name.',
      );
    }
    items.add(out);
  }
  return items;
}

/// Checks the number of parameters of an event once the default parameters are merged in. The two session
/// parameters the client adds count against the limit.
void checkParameterCount(int count) {
  final int allowed =
      AnalyticsLimits.maxParametersPerEvent - clientParameterNames.length;
  if (count > allowed) {
    throw _error(
      'too-many-parameters',
      'The event has $count parameters, default parameters included; at most $allowed are allowed, since the '
          'client adds session_id and engagement_time_msec.',
    );
  }
}

/// Checks a user property name and value; a null [value] removes the property and is always allowed.
void checkUserProperty(String name, String? value) {
  if (name.isEmpty ||
      name.length > AnalyticsLimits.maxUserPropertyNameLength ||
      !_namePattern.hasMatch(name)) {
    throw _error(
      'invalid-user-property',
      'User property name "${_shown(name)}" must be 1 to ${AnalyticsLimits.maxUserPropertyNameLength} letters, '
          'digits or underscores, starting with a letter.',
    );
  }
  if (reservedUserPropertyNames.contains(name)) {
    throw _error(
      'reserved-name',
      'User property name "$name" is reserved by the Measurement Protocol${name == 'user_id' ? '; use setUserId' : ''}.',
    );
  }
  for (final String prefix in reservedUserPropertyPrefixes) {
    if (name.startsWith(prefix)) {
      throw _error(
        'reserved-name',
        'User property name "$name" starts with the reserved prefix "$prefix".',
      );
    }
  }
  if (value != null &&
      measuredLength(value) > AnalyticsLimits.maxUserPropertyValueLength) {
    throw _error(
      'invalid-user-property',
      'The value of user property "$name" is longer than ${AnalyticsLimits.maxUserPropertyValueLength} '
          'characters, counted in its percent-encoded form.',
    );
  }
}

/// Checks a user id; null clears it and is always allowed.
void checkUserId(String? id) {
  if (id == null) {
    return;
  }
  if (id.isEmpty || measuredLength(id) > AnalyticsLimits.maxUserIdLength) {
    throw _error(
      'invalid-user-id',
      'The user id must be 1 to ${AnalyticsLimits.maxUserIdLength} characters, counted in its percent-encoded '
          'form; pass null to clear it.',
    );
  }
}

/// The number of UTF-8 bytes of [json] encoded.
int encodedSize(Object json) => utf8.encode(jsonEncode(json)).length;

/// A name as shown in a message: cut, with control characters removed.
String _shown(String name) {
  final String clean = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '?');
  return clean.length <= 60 ? clean : '${clean.substring(0, 60)}…';
}
