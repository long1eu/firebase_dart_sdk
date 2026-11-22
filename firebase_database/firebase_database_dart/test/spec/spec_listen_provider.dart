// The fake ListenProvider of the syncPointSpec runner (JS `SyncPointListenProvider` in
// syncpoint-util.ts, Android `getNewListenProvider` in SyncPointTest.java).
//
// startListening returns List<Event> (seam change C19). It compiles against the older `void`
// signature too, because any return type may override `void`.
library;

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

/// A listen provider that keeps the set of active listens and fails on a duplicate start or on a
/// stop of a listen it does not have (both upstream runners). Listens never complete, and a start
/// raises no events.
final class SpecListenProvider implements ListenProvider {
  final Map<String, ({QuerySpec query, Tag? tag})> _active =
      <String, ({QuerySpec query, Tag? tag})>{};

  /// Every start and stop, in order, for failure messages.
  final List<String> log = <String>[];

  /// The keys of the active listens.
  Iterable<String> get activeListens => _active.keys;

  /// The key of a listen: path, query identifier and tag (JS `getQueryKey`).
  static String keyOf(QuerySpec query, Tag? tag) =>
      '${query.path}|${query.params.toQueryIdentifier()}'
      '${tag == null ? '' : '|${tag.number}'}';

  @override
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  ) {
    final String key = keyOf(query, tag);
    log.add('start $key');
    if (_active.containsKey(key)) {
      fail('Duplicate listen: $key');
    }
    _active[key] = (query: query, tag: tag);
    return const <Event>[];
  }

  @override
  void stopListening(QuerySpec query, Tag? tag) {
    final String key = keyOf(query, tag);
    log.add('stop $key');
    if (_active.remove(key) == null) {
      fail("Missing record of query that we're removing: $key");
    }
  }
}
