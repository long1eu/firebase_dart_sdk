// The internal side of the public API classes.
//
// The members of the public classes that only the SDK may use (model keys and
// documents, core queries, the client of an instance, constructors, ...) are
// library private. Each class file declares an `...Internal` extension next to
// the class that gives the rest of the SDK access to them, and the public
// libraries (cloud_firestore_dart.dart, lite.dart, pipelines.dart) do not
// export those extensions.
//
// Code inside `lib/src` imports the class files directly. This library
// collects all the extensions for code that imports a public library, such as
// the tests. It is not part of the supported API.

export 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart'
    show AggregateFieldInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query.dart'
    show AggregateQueryInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query_snapshot.dart'
    show AggregateQuerySnapshotInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/document_change.dart'
    show DocumentChangeInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart'
    show DocumentReferenceInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart'
    show DocumentSnapshotInternal, QueryDocumentSnapshotInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart'
    show FieldPathInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    show FieldValueInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart'
    show FirestoreInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task.dart'
    show LoadBundleTaskInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task_progress.dart'
    show LoadBundleTaskProgressInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/persistent_cache_index_manager.dart'
    show PersistentCacheIndexManagerInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/query.dart'
    show QueryInternal, CollectionReferenceInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart'
    show QuerySnapshotInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart'
    show SetOptionsInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/transaction.dart'
    show TransactionInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/vector_query.dart'
    show VectorQueryInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/vector_query_snapshot.dart'
    show VectorQuerySnapshotInternal;
export 'package:cloud_firestore_dart/src/firebase/firestore/write_batch.dart'
    show WriteBatchInternal;
export 'package:cloud_firestore_dart/src/firebase/timestamp.dart'
    show TimestampInternal;
