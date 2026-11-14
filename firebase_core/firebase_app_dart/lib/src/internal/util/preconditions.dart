// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

/// Argument and state checks that throw when they fail.
class Preconditions {
  /// Not needed: every member of [Preconditions] is static.
  Preconditions();

  /// Throws a [StateError] with [message] unless [condition] holds.
  static void checkState(bool condition, Object? message) {
    if (!condition) {
      throw StateError('$message');
    }
  }

  /// Returns [object], or throws an [ArgumentError] if it is `null`.
  static T checkNotNull<T>(T? object, [String? message]) {
    if (object == null) {
      throw ArgumentError('$message ${T.toString()}');
    } else {
      return object;
    }
  }

  /// Returns [value], or throws an [ArgumentError] with [message] if it is `null` or empty.
  static String checkNotEmpty(String? value, String message) {
    if (value == null || value.isEmpty) {
      throw ArgumentError(message);
    } else {
      return value;
    }
  }

  /// Ensures the truth of an expression involving one or more parameters to the
  /// calling method.
  static void checkArgument(bool condition, String errorMessage) {
    if (!condition) {
      throw ArgumentError(errorMessage);
    }
  }
}
