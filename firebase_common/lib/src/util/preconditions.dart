// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

class Preconditions {
  static void checkState(bool condition, Object message) {
    if (!condition) {
      throw StateError('$message');
    }
  }

  static T checkNotNull<T>(T object) {
    if (object == null) {
      throw ArgumentError('${T.toString()}');
    } else {
      return object;
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
