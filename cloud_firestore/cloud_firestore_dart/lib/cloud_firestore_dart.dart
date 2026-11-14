/// A pure-Dart Cloud Firestore client for the Dart VM and Flutter, with
/// experimental web support (REST and WebChannel over `fetch`).
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
///
/// The value types shared with `package:cloud_firestore_dart/lite.dart` are
/// documented here.
///
/// {@canonicalFor aggregate_field.AggregateField}
/// {@canonicalFor aggregate_field.AverageAggregateField}
/// {@canonicalFor aggregate_field.CountAggregateField}
/// {@canonicalFor aggregate_field.SumAggregateField}
/// {@canonicalFor blob.Blob}
/// {@canonicalFor bson_object_id.BsonObjectId}
/// {@canonicalFor bson_timestamp.BsonTimestamp}
/// {@canonicalFor decimal128_value.Decimal128Value}
/// {@canonicalFor field_path.FieldPath}
/// {@canonicalFor field_value.FieldValue}
/// {@canonicalFor filter.Filter}
/// {@canonicalFor firestore_error.FirestoreError}
/// {@canonicalFor firestore_error.FirestoreErrorCode}
/// {@canonicalFor geo_point.GeoPoint}
/// {@canonicalFor int32_value.Int32Value}
/// {@canonicalFor log_level.LogLevel}
/// {@canonicalFor max_key.MaxKey}
/// {@canonicalFor min_key.MinKey}
/// {@canonicalFor query.Direction}
/// {@canonicalFor regex_value.RegexValue}
/// {@canonicalFor set_options.SetOptions}
/// {@canonicalFor timestamp.Timestamp}
/// {@canonicalFor transaction_options.TransactionOptions}
/// {@canonicalFor vector_value.VectorValue}
library;

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
export 'src/firebase/firestore/decimal128_value.dart'
    hide Decimal128ValueInternal;
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
        ExclusiveDatabase,
        OnConfigure,
        OnCreate,
        OnOpen,
        OnVersionChange,
        OpenDatabase,
        TransientDatabaseException;
export 'src/firebase/firestore/vector_query.dart' show VectorQuery;
export 'src/firebase/firestore/vector_query_snapshot.dart'
    hide VectorQuerySnapshotInternal;
export 'src/firebase/firestore/vector_value.dart';
export 'src/firebase/firestore/write_batch.dart' hide WriteBatchInternal;
export 'src/firebase/timestamp.dart' hide TimestampInternal;
