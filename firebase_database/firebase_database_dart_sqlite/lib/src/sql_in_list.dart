/// `IN (?, ...)` lists whose SQL text comes in few sizes, so that the connection's cache of
/// prepared statements keeps a handful of texts per query instead of one per list length.
///
/// A list is padded to the next size of [sizes] by repeating its last value; a repeated value
/// changes neither an `IN` test nor a `DELETE ... IN`.
abstract final class SqlInList {
  /// The list sizes; the last one is the most values one statement binds
  /// (`SQLITE_MAX_VARIABLE_NUMBER` was 999 before SQLite 3.32).
  static const List<int> sizes = <int>[1, 4, 16, 64, 256, 512];

  /// The most values in one list.
  static int get maxSize => sizes.last;

  /// The size of [length] values, padded.
  static int paddedLength(int length) {
    for (final int size in sizes) {
      if (length <= size) {
        return size;
      }
    }
    throw ArgumentError.value(length, 'length', 'more than $maxSize values');
  }

  /// `?, ?, ...` for [values] once padded.
  static String marks(List<Object?> values) =>
      List<String>.filled(paddedLength(values.length), '?').join(', ');

  /// [values] padded to [paddedLength] by repeating the last one; [values] must not be empty.
  static List<Object?> pad(List<Object?> values) => <Object?>[
    ...values,
    for (int i = values.length; i < paddedLength(values.length); i++)
      values.last,
  ];

  /// [values] cut into lists of at most [maxSize].
  static Iterable<List<T>> chunks<T>(List<T> values) sync* {
    for (int start = 0; start < values.length; start += maxSize) {
      final int end = start + maxSize < values.length
          ? start + maxSize
          : values.length;
      yield values.sublist(start, end);
    }
  }
}
