/// A pure-Dart Cloud Firestore client for the Dart VM and Flutter (no web).
///
/// Start from [Firestore.instanceFor] with a `FirebaseApp` created with
/// `package:firebase_app_dart`, then use [Firestore.collection] and
/// [Firestore.doc] to get a [CollectionReference] or a [DocumentReference].
/// Reads return a [DocumentSnapshot] or a [QuerySnapshot]; `snapshots` streams
/// deliver updates in real time. Writes go through [DocumentReference.set],
/// [DocumentReference.update], a [WriteBatch] or a [Transaction].
///
/// The offline cache is stored in SQLite when an [OpenDatabase] function is
/// supplied, and in memory otherwise.
library cloud_firestore_dart;

export 'src/firebase/firestore/aggregate_field.dart'
    hide AggregateFieldInternal;
export 'src/firebase/firestore/aggregate_query.dart'
    hide AggregateQueryInternal;
export 'src/firebase/firestore/aggregate_query_snapshot.dart'
    hide AggregateQuerySnapshotInternal;
export 'src/firebase/firestore/aggregate_source.dart';
export 'src/firebase/firestore/aliases.dart';
export 'src/firebase/firestore/blob.dart';
export 'src/firebase/firestore/bson_object_id.dart';
export 'src/firebase/firestore/bson_timestamp.dart';
export 'src/firebase/firestore/decimal128_value.dart';
export 'src/firebase/firestore/distance_measure.dart';
export 'src/firebase/firestore/document_change.dart'
    hide DocumentChangeInternal;
export 'src/firebase/firestore/document_reference.dart'
    hide DocumentReferenceInternal;
export 'src/firebase/firestore/document_snapshot.dart'
    hide DocumentSnapshotInternal, QueryDocumentSnapshotInternal;
export 'src/firebase/firestore/field_path.dart' hide FieldPathInternal;
export 'src/firebase/firestore/field_value.dart' hide FieldValueInternal;
export 'src/firebase/firestore/filter.dart' show Filter;
export 'src/firebase/firestore/firestore.dart' hide FirestoreInternal;
export 'src/firebase/firestore/firestore_data_converter.dart';
export 'src/firebase/firestore/firestore_error.dart';
export 'src/firebase/firestore/firestore_settings.dart';
export 'src/firebase/firestore/geo_point.dart';
export 'src/firebase/firestore/int32_value.dart';
export 'src/firebase/firestore/listen_source.dart';
export 'src/firebase/firestore/load_bundle_task.dart'
    hide LoadBundleTaskInternal;
export 'src/firebase/firestore/load_bundle_task_progress.dart'
    hide LoadBundleTaskProgressInternal;
export 'src/firebase/firestore/log_level.dart' show LogLevel;
export 'src/firebase/firestore/local_cache_settings.dart';
export 'src/firebase/firestore/max_key.dart';
export 'src/firebase/firestore/metadata_change.dart';
export 'src/firebase/firestore/min_key.dart';
export 'src/firebase/firestore/persistent_cache_index_manager.dart'
    hide PersistentCacheIndexManagerInternal;
export 'src/firebase/firestore/query.dart'
    hide QueryInternal, CollectionReferenceInternal;
export 'src/firebase/firestore/query_snapshot.dart' hide QuerySnapshotInternal;
export 'src/firebase/firestore/regex_value.dart';
export 'src/firebase/firestore/server_timestamp_behavior.dart';
export 'src/firebase/firestore/set_options.dart' hide SetOptionsInternal;
export 'src/firebase/firestore/snapshot_listen_options.dart';
export 'src/firebase/firestore/snapshot_metadata.dart';
export 'src/firebase/firestore/source.dart';
export 'src/firebase/firestore/transaction.dart' hide TransactionInternal;
export 'src/firebase/firestore/transaction_options.dart';
export 'src/firebase/firestore/util/database.dart'
    show
        ClearableDatabase,
        Database,
        OnConfigure,
        OnCreate,
        OnOpen,
        OnVersionChange,
        OpenDatabase;
export 'src/firebase/firestore/vector_query.dart' show VectorQuery;
export 'src/firebase/firestore/vector_query_snapshot.dart'
    hide VectorQuerySnapshotInternal;
export 'src/firebase/firestore/vector_value.dart';
export 'src/firebase/firestore/write_batch.dart' hide WriteBatchInternal;
export 'src/firebase/timestamp.dart' hide TimestampInternal;
