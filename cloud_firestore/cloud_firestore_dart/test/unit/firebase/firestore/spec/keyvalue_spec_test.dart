import 'dart:async';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';
import '../local/persistence_test_helpers.dart';
import 'spec_runner.dart';
import 'spec_skip_list.dart';

/// Runs the upstream JSON spec tests on the key-value cache over the in-memory `MemoryLogStore` of the examples. A
/// client that restarts opens the store of its spec again, so the durable-persistence specs run.
void main() {
  final Map<String, _SpecStore> stores = <String, _SpecStore>{};
  registerSpecTests(
    variant: 'keyvalue',
    getPersistence: (_, String name) async {
      final _SpecStore store = stores.putIfAbsent(name, _SpecStore.new);
      // A restart releases the persistence of the client while it starts the new one: a store is the cache of one
      // persistence at a time.
      await store.closed;
      return createKeyValuePersistence(
        store: store,
        // The bundle specs carry documents of project 'test-project', which the persistence must be able to decode.
        projectId: 'test-project',
      );
    },
    excludedTags: keyValueExcludedTags,
  );
}

/// A [MemoryLogStore] that tells when it is closed.
class _SpecStore extends MemoryLogStore {
  Completer<void>? _open;

  /// Completes once the store is closed (at once when it is not open).
  Future<void> get closed => _open?.future ?? Future<void>.value();

  @override
  Future<void> open() async {
    _open = Completer<void>();
    await super.open();
  }

  @override
  Future<void> close() async {
    await super.close();
    _open?.complete();
    _open = null;
  }
}
