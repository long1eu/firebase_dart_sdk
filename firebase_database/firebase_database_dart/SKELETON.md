# firebase_database_dart skeleton

Signature-only core of the Realtime Database client. Every body is `throw UnimplementedError()` except
constants, trivial field-holding constructors, `CachePolicy.none`, and the two files under `lib/src/testing/`
(real code, frozen test support). One Dart file per upstream file; each file's first doc line names the JS
(`packages/database/src`, a086865) and Android (`firebase-database/src/main/java/com/google/firebase/database`,
2cfdd03) sources. `dart analyze` is clean; the `avoid_unused_constructor_parameters` lint is off in
`analysis_options.yaml` for the skeleton phase only (factories throw before using their parameters).

## Owner slots and build order

| Slot | Who | Builds after |
|---|---|---|
| SHARED | boss, already final (small types) | - |
| DL1 | numbers, key order, hash, push ids, ChildKey, Path, validation | SHARED |
| DL2 | sorted map, nodes, indexes, JSON | DL1 |
| DL3 | CompoundWrite, ImmutableTree, server values, query params/spec, compound hash, range merge | DL2 |
| SEAM-CONN | connection seam (JSON only), interfaces final | - (implemented by the connection team under `lib/src/realtime/`, which that team stubs) |
| SEAM | ListenProvider, SyncTreeApi, PersistenceManager, interfaces final | DL3 for types |
| SYNC | operations, views, filters, write tree, sync point, sync tree, NoopPersistenceManager | data-layer freeze |
| PERSIST | storage engine, tracked queries, pruning, managers | data-layer freeze; sync tree for the end-to-end tests |
| REPO | Repo, transactions, onDisconnect, `.info`, event queue | SYNC |
| FROZEN | real test support, written now | data layer, to run |

Contract tests (written, not run yet): `test/contract/server_actions_contract_test.dart` (runs against
`FakeServerActions` now; the connection team adds its harness), `persistence_storage_engine_contract_test.dart`,
`persistence_manager_contract_test.dart` (Noop, Default, WritesOnly), `sync_tree_api_contract_test.dart`,
`listen_provider_contract_test.dart` (RepoListenProvider over FakeServerActions). They need the data layer filled.

## Files

Paths are under `lib/src/`. Android paths are relative to `com/google/firebase/database/` without `.java`.
"Depends on" lists the package files imported (doc-only imports included).

| File | Owner | JS | Android | Depends on |
|---|---|---|---|---|
| `core/write_id.dart` | SHARED | core/Repo.ts (nextWriteId_) | core/Repo.java | - |
| `core/tag.dart` | SHARED | core/SyncTree.ts (number tags) | core/Tag.java | - |
| `core/database_error.dart` | SHARED | core/util/util.ts errorForServerCode | DatabaseError.java | - |
| `core/util/clock.dart` | SHARED | core/Repo.ts repoServerTime | core/utilities/Clock, OffsetClock | - |
| `core/util/numbers.dart` | DL1 | core/util/util.ts (part) | snapshot/LongNode, DoubleNode | - |
| `core/util/key_order.dart` | DL1 | core/util/util.ts nameCompare | snapshot/ChildKey (compareTo) | child_key |
| `core/util/hash.dart` | DL1 | core/util/util.ts sha1 | core/utilities/Utilities | - |
| `core/util/push_id.dart` | DL1 | core/util/NextPushId.ts | core/utilities/PushIdGenerator | - |
| `core/snap/child_key.dart` | DL1 | (strings) | snapshot/ChildKey | - |
| `core/path.dart` | DL1 | core/util/Path.ts | core/Path, core/ValidationPath | child_key |
| `core/util/validation.dart` | DL1 | core/util/validation.ts | core/utilities/Validation | path |
| `core/util/sorted_map.dart` | DL2 | core/util/SortedMap.ts | collection/ImmutableSortedMap (copy Firestore database_collection) | - |
| `core/snap/node.dart` | DL2 | core/snap/Node.ts | snapshot/Node | path, child_key, children_node, index, leaf_node |
| `core/snap/named_node.dart` | DL2 | core/snap/Node.ts (NamedNode) | snapshot/NamedNode | child_key, node |
| `core/snap/leaf_node.dart` | DL2 | core/snap/LeafNode.ts | snapshot/LeafNode + Boolean/Long/Double/String/DeferredValueNode | path, child_key, index, node |
| `core/snap/children_node.dart` | DL2 | core/snap/ChildrenNode.ts | snapshot/ChildrenNode, EmptyNode, IndexedNode | path, child_key, index_map, index, named_node, node, sorted_map |
| `core/snap/priority.dart` | DL2 | core/snap/snap.ts | snapshot/PriorityUtilities | node |
| `core/snap/comparators.dart` | DL2 | core/snap/comparators.ts | - | child_key, named_node |
| `core/snap/index_map.dart` | DL2 | core/snap/IndexMap.ts | (IndexedNode) | child_key, index, named_node, node, sorted_map |
| `core/snap/child_set.dart` | DL2 | core/snap/childSet.ts | collection/RBTreeSortedMap builder | named_node, sorted_map |
| `core/snap/node_from_json.dart` | DL2 | core/snap/nodeFromJSON.ts | snapshot/NodeUtilities | node |
| `core/snap/indexes/index.dart` | DL2 | core/snap/indexes/Index.ts | snapshot/Index | child_key, named_node, node |
| `core/snap/indexes/key_index.dart` | DL2 | core/snap/indexes/KeyIndex.ts | snapshot/KeyIndex | child_key, index, named_node, node |
| `core/snap/indexes/priority_index.dart` | DL2 | core/snap/indexes/PriorityIndex.ts | snapshot/PriorityIndex | child_key, index, named_node, node |
| `core/snap/indexes/value_index.dart` | DL2 | core/snap/indexes/ValueIndex.ts | snapshot/ValueIndex | child_key, index, named_node, node |
| `core/snap/indexes/path_index.dart` | DL2 | core/snap/indexes/PathIndex.ts | snapshot/PathIndex | path, child_key, index, named_node, node |
| `core/compound_write.dart` | DL3 | core/CompoundWrite.ts | core/CompoundWrite | path, child_key, named_node, node, immutable_tree |
| `core/util/immutable_tree.dart` | DL3 | core/util/ImmutableTree.ts | core/utilities/ImmutableTree | path, child_key, sorted_map |
| `core/util/server_values.dart` | DL3 | core/util/ServerValues.ts | core/ServerValues, core/ValueProvider | compound_write, path, child_key, node, write_id |
| `core/util/node_size_estimator.dart` | DL3 | - | core/utilities/NodeSizeEstimator | node |
| `core/snap/compound_hash.dart` | DL3 | - | snapshot/CompoundHash | path, node |
| `core/snap/range_merge.dart` | DL3 | - | snapshot/RangeMerge | wire_range_merge, path, node |
| `core/view/query_params.dart` | DL3 | core/view/QueryParams.ts | core/view/QueryParams | child_key, index, node |
| `core/view/query_spec.dart` | DL3 | QueryContext (view/EventRegistration.ts) | core/view/QuerySpec | listen_spec, path, index, query_params |
| `core/connection/server_actions.dart` | SEAM-CONN | core/ServerActions.ts + Repo.ts callbacks | connection/PersistentConnection (+Delegate) | listen_hash_provider, listen_spec, wire_range_merge |
| `core/connection/listen_spec.dart` | SEAM-CONN | QueryContext as listen reads it | PersistentConnection.listen args | server_actions |
| `core/connection/listen_hash_provider.dart` | SEAM-CONN | currentHashFn | connection/ListenHashProvider, connection/CompoundHash | - |
| `core/connection/wire_range_merge.dart` | SEAM-CONN | - | connection/RangeMerge | - |
| `core/listen_provider.dart` | SEAM | core/SyncTree.ts ListenProvider | core/SyncTree.ListenProvider | listen_hash_provider, database_error, tag, event, query_spec |
| `core/sync_tree_api.dart` | SEAM | core/SyncTree.ts exports | core/SyncTree (public methods) | compound_write, database_error, event_registration, path, persistence_manager, node, range_merge, tag, clock, cache_node, event, query_spec, write_id |
| `core/persistence/persistence_manager.dart` | SEAM | - | core/persistence/PersistenceManager | compound_write, path, noop_persistence_manager, child_key, node, user_write_record, cache_node, query_spec, write_id |
| `core/operation/operation.dart` | SYNC | core/operation/Operation.ts | core/operation/Operation | compound_write, operation_source, path, child_key, node, immutable_tree |
| `core/operation/operation_source.dart` | SYNC | core/operation/Operation.ts | core/operation/OperationSource | query_params |
| `core/operation/overwrite.dart` | SYNC | core/operation/Overwrite.ts | core/operation/Overwrite | - |
| `core/operation/merge.dart` | SYNC | core/operation/Merge.ts | core/operation/Merge | - |
| `core/operation/ack_user_write.dart` | SYNC | core/operation/AckUserWrite.ts | core/operation/AckUserWrite | - |
| `core/operation/listen_complete.dart` | SYNC | core/operation/ListenComplete.ts | core/operation/ListenComplete | - |
| `core/event_registration.dart` | SYNC | core/view/EventRegistration.ts | core/EventRegistration | database_error, change, event, query_spec |
| `core/view/event.dart` | SYNC | core/view/Event.ts | core/view/Event | database_error, event_registration, path, child_key, node |
| `core/view/data_event.dart` | SYNC | core/view/Event.ts | core/view/DataEvent | - |
| `core/view/cancel_event.dart` | SYNC | core/view/Event.ts | core/view/CancelEvent | - |
| `core/view/change.dart` | SYNC | core/view/Change.ts | core/view/Change | child_key, node, event |
| `core/view/cache_node.dart` | SYNC | core/view/CacheNode.ts | core/view/CacheNode | path, child_key, node |
| `core/view/view_cache.dart` | SYNC | core/view/ViewCache.ts | core/view/ViewCache | node, cache_node |
| `core/view/complete_child_source.dart` | SYNC | core/view/CompleteChildSource.ts | view/filter/NodeFilter.CompleteChildSource, ViewProcessor | child_key, index, named_node, node, view_cache, write_tree_ref |
| `core/view/filter/child_change_accumulator.dart` | SYNC | core/view/ChildChangeAccumulator.ts | core/view/filter/ChildChangeAccumulator | change |
| `core/view/filter/node_filter.dart` | SYNC | core/view/filter/NodeFilter.ts | core/view/filter/NodeFilter | path, child_key, index, node, complete_child_source, child_change_accumulator, query_params |
| `core/view/filter/indexed_filter.dart` | SYNC | core/view/filter/IndexedFilter.ts | core/view/filter/IndexedFilter | path, child_key, index, node, complete_child_source, child_change_accumulator, node_filter |
| `core/view/filter/ranged_filter.dart` | SYNC | core/view/filter/RangedFilter.ts | core/view/filter/RangedFilter | path, child_key, index, named_node, node, complete_child_source, child_change_accumulator, node_filter, query_params |
| `core/view/filter/limited_filter.dart` | SYNC | core/view/filter/LimitedFilter.ts | core/view/filter/LimitedFilter | path, child_key, index, node, complete_child_source, child_change_accumulator, node_filter, query_params |
| `core/view/view_processor.dart` | SYNC | core/view/ViewProcessor.ts | core/view/ViewProcessor | operation, path, node, change, child_change_accumulator, node_filter, view_cache, write_tree_ref |
| `core/view/event_generator.dart` | SYNC | core/view/EventGenerator.ts | core/view/EventGenerator | event_registration, node, change, event, query_spec |
| `core/view/view.dart` | SYNC | core/view/View.ts | core/view/View | database_error, event_registration, operation, path, node, change, event, query_spec, view_cache, write_tree_ref |
| `core/user_write_record.dart` | SYNC | core/WriteTree.ts WriteRecord | core/UserWriteRecord | compound_write, path, node, write_id |
| `core/write_tree.dart` | SYNC | core/WriteTree.ts | core/WriteTree | compound_write, path, child_key, index, named_node, node, user_write_record, cache_node, write_id, write_tree_ref |
| `core/write_tree_ref.dart` | SYNC | core/WriteTree.ts WriteTreeRef | core/WriteTreeRef | path, child_key, index, named_node, node, cache_node, write_id, write_tree |
| `core/sync_point.dart` | SYNC | core/SyncPoint.ts | core/SyncPoint | database_error, event_registration, operation, path, persistence_manager, node, cache_node, event, query_params, query_spec, view, write_tree_ref |
| `core/sync_tree.dart` | SYNC | core/SyncTree.ts | core/SyncTree (+KeepSyncedEventRegistration) | compound_write, database_error, event_registration, listen_provider, path, persistence_manager, node, range_merge, sync_point, sync_tree_api, tag, clock, immutable_tree, cache_node, change, event, query_spec, write_id, write_tree |
| `core/persistence/noop_persistence_manager.dart` | SYNC | - | core/persistence/NoopPersistenceManager | compound_write, path, persistence_manager, child_key, node, user_write_record, cache_node, query_spec, write_id |
| `core/persistence/persistence_storage_engine.dart` | PERSIST | - | core/persistence/PersistenceStorageEngine | compound_write, path, prune_forest, tracked_query, child_key, node, user_write_record, write_id |
| `core/persistence/persistence_storage_engine_opener.dart` | PERSIST | - | core/Platform.createPersistenceManager | persistence_storage_engine |
| `core/persistence/tracked_query.dart` | PERSIST | - | core/persistence/TrackedQuery | query_spec |
| `core/persistence/prune_forest.dart` | PERSIST | - | core/persistence/PruneForest | path, child_key, immutable_tree |
| `core/persistence/cache_policy.dart` | PERSIST | - | core/persistence/CachePolicy | - |
| `core/persistence/lru_cache_policy.dart` | PERSIST | - | core/persistence/LRUCachePolicy | cache_policy |
| `core/persistence/tracked_query_manager.dart` | PERSIST | - | core/persistence/TrackedQueryManager | path, cache_policy, persistence_storage_engine, prune_forest, tracked_query, child_key, clock, query_spec |
| `core/persistence/default_persistence_manager.dart` | PERSIST | - | core/persistence/DefaultPersistenceManager | compound_write, path, cache_policy, persistence_manager, persistence_storage_engine, child_key, node, user_write_record, clock, cache_node, query_spec, write_id |
| `core/persistence/writes_only_persistence_manager.dart` | PERSIST | - | (split of DefaultPersistenceManager, design 13a) | compound_write, path, default_persistence_manager, noop_persistence_manager, persistence_manager, persistence_storage_engine, child_key, node, user_write_record, cache_node, query_spec, write_id |
| `core/repo.dart` | REPO | core/Repo.ts | core/Repo | compound_write, listen_hash_provider, server_actions, wire_range_merge, database_error, event_registration, listen_provider, path, noop_persistence_manager, persistence_manager, repo_info, node, snapshot_holder, sync_tree_api, tag, transaction_data, clock, event, event_queue, query_spec |
| `core/repo_info.dart` | REPO | core/RepoInfo.ts (part) | core/RepoInfo | - |
| `core/transaction_data.dart` | REPO | core/Repo.ts Transaction | core/Repo.TransactionData, Transaction.Handler | database_error, path, node, write_id |
| `core/util/tree.dart` | REPO | core/util/Tree.ts | core/utilities/Tree, TreeNode | path, child_key |
| `core/sparse_snapshot_tree.dart` | REPO | core/SparseSnapshotTree.ts | core/SparseSnapshotTree | path, child_key, node |
| `core/snapshot_holder.dart` | REPO | core/SnapshotHolder.ts | core/SnapshotHolder | path, node |
| `core/view/event_queue.dart` | REPO | core/view/EventQueue.ts | core/view/EventRaiser | path, event |
| `testing/fake_server_actions.dart` | FROZEN (real) | - | - | listen_hash_provider, listen_spec, server_actions, wire_range_merge |
| `testing/in_memory_persistence_storage_engine.dart` | FROZEN (real) | - | testUtil MockPersistenceStorageEngine | compound_write, path, persistence_storage_engine, prune_forest, tracked_query, child_key, children_node, priority_index, node, user_write_record, node_size_estimator, write_id |

`lib/firebase_database_dart.dart` is a placeholder library (no exports); the public API is a later contract.

Not here on purpose: `lib/src/realtime/*`, `PersistentConnection`, the REST client (connection team); the public API
(`FirebaseDatabase`, `DatabaseReference`, `Query`, `DataSnapshot`, event streams, `OnDisconnect`, `ServerValue`);
`io.dart` with the SQLite engine factory.

## Places where JS and Android disagree and which one the signature follows

| Topic | JS | Android | Signature follows |
|---|---|---|---|
| Sync tree structure | free functions over structs, no persistence | classes with a `PersistenceManager` everywhere | Android (decision 1) |
| Child names | `string` + `nameCompare` | `ChildKey` with parsed int | Android `ChildKey` (addendum E); `key_order.dart` keeps the string helpers |
| Numbers | one `number` | `LongNode` / `DoubleNode` | one `LeafNode` with `num`, JS rule (integral within 2^53) on every platform |
| Indexes on nodes | `ChildrenNode` carries an `IndexMap` | `IndexedNode` wrapper | JS: views pass plain `Node` where Android passes `IndexedNode`; no `IndexedNode` class |
| Index post value | `makePost(indexValue: unknown, name)` (JSON) | `makePost(ChildKey, Node)` | Android: query bounds are `Node`s |
| Query bounds | `startAfter`/`endBefore` flags, `sin`/`ein` on the wire | only `startAt`/`endAt` | JS (`startInclusive`/`endInclusive`, `startAfter`, `endBefore`); emulator probe Q3 decides the wire |
| `getNodeFilter` | in `QueryParams.ts` | in `QueryParams.java` | top-level `nodeFilterFor` in `view/filter/node_filter.dart`, so the data layer does not depend on views |
| Server cache in `SyncPoint.getView` | `Node?` + `serverCacheComplete` | `CacheNode` | Android `CacheNode` |
| Merges | plain maps / `ImmutableTree` | `CompoundWrite` | Android `CompoundWrite` (in the data layer) |
| `applyUserOverwrite`/`Merge`/`ack` | no `persist`, no unresolved data, no clock | `persist`, unresolved node, `serverClock` | Android |
| `removeAllWrites`, `keepSynced`, `getServerValue`, `persistenceServerCache` | absent | present | Android |
| Range merges and compound hash | absent | present | Android (boss answer 3) |
| `ListenProvider.startListening` | returns `Event[]`, hash as a function | void, `ListenHashProvider` + completion returning events | Android |
| Tag counter | module global | instance field | per instance (addendum D) |
| Listen completion | `(status, data)` | `DatabaseError?` | Android inside the tree (`ListenCompletion(DatabaseError?)`); JS `(status, data)` across the connection seam |
| `Event` objects | `DataEvent` holds an API `DataSnapshot` | holds `DataSnapshot` | internal: `DataEvent` holds path + `Node`; the public snapshot wraps it later |
| Event dispatch | `EventQueue` orders by path | `EventRaiser` posts to a run loop | JS `EventQueue` with an injected `EventTarget` |
| `EventRegistration` | `matches`, `hasAnyCallback`, `createCancelEvent` | `isSameListener`, `clone`, zombies | Android |
| Path on the wire | `/a/b` | `a/b` | JS `/a/b` (protocol spec section 11) |
| Seam write callback | `(status, data)` | `(errorCode?, errorMessage?)` | JS: status string always present (`ok`, server code, local `disconnect`) |
| Error codes | `Error(CODE)` from the status | int codes + reason table | kebab-case `DatabaseErrorCode` with the wire status |
| `PersistenceStorageEngine.loadTrackedQueryKeys` | - | two overloads | one method taking `Set<int>` (storage engine design section 1) |
| Persistence errors | - | rethrown as `RuntimeException` | never thrown; engine degrades, `isDurable` turns false (addendum 4) |
