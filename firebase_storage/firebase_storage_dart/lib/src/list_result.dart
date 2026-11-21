import 'package:meta/meta.dart';

import 'reference.dart';

/// A page of `Reference.list`: the objects and the "folders" (prefixes) directly under a reference.
@immutable
final class ListResult {
  /// Creates a result; the package creates them, you need this only in tests.
  const ListResult({
    required this.items,
    required this.prefixes,
    this.nextPageToken,
  });

  /// The objects directly under the listed reference.
  final List<Reference> items;

  /// The prefixes directly under the listed reference: the paths that have objects below them, without the
  /// trailing slash.
  final List<Reference> prefixes;

  /// Pass it as `pageToken` to `Reference.list` for the next page; null on the last page.
  final String? nextPageToken;

  @override
  String toString() =>
      'ListResult(items: $items, prefixes: $prefixes, nextPageToken: $nextPageToken)';
}
