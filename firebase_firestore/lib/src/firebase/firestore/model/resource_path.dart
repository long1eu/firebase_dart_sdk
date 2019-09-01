// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/base_path.dart';

/// A slash separated path for navigating resources (documents and collections)
/// within Firestore.
class ResourcePath extends BasePath<ResourcePath> {
  const ResourcePath._([List<String> segments = const <String>[]])
      : super(segments);

  factory ResourcePath.fromSegments(List<String> segments) {
    return segments.isEmpty ? empty : ResourcePath._(segments);
  }

  factory ResourcePath.fromString(String path) {
    // NOTE: The client is ignorant of any path segments containing escape
    // sequences (e.g. __id123__) and just passes them through raw (they exist
    // for legacy reasons and should not be used frequently).

    if (path.contains('//')) {
      throw ArgumentError(
          'Invalid path ($path). Paths must not contain // in them.');
    }

    // We may still have an empty segment at the beginning or end if they had a
    // leading or trailing slash (which we allow).
    final List<String> rawSegments = path.split('/');
    final List<String> segments = <String>[];
    for (String segment in rawSegments) {
      if (segment.isNotEmpty) {
        segments.add(segment);
      }
    }

    return ResourcePath._(segments.toList(growable: false));
  }

  static const ResourcePath empty = ResourcePath._();

  @override
  ResourcePath createPathWithSegments(List<String> segments) {
    return ResourcePath._(segments);
  }

  @override
  String get canonicalString {
    // NOTE: The client is ignorant of any path segments containing escape
    // sequences (e.g. __id123__) and just passes them through raw (they exist
    // for legacy reasons and should not be used frequently).
    final StringBuffer builder = StringBuffer();
    for (int i = 0; i < length; i++) {
      if (i > 0) {
        builder.write('/');
      }
      builder.write(segments[i]);
    }
    return builder.toString();
  }
}
