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

export 'src/firebase/firestore/aggregate_field.dart';
export 'src/firebase/firestore/aggregate_query.dart';
export 'src/firebase/firestore/aggregate_query_snapshot.dart';
export 'src/firebase/firestore/aggregate_source.dart';
export 'src/firebase/firestore/aliases.dart';
export 'src/firebase/firestore/blob.dart';
export 'src/firebase/firestore/collection_reference.dart';
export 'src/firebase/firestore/distance_measure.dart';
export 'src/firebase/firestore/document_change.dart';
export 'src/firebase/firestore/document_reference.dart';
export 'src/firebase/firestore/document_snapshot.dart';
export 'src/firebase/firestore/field_path.dart';
export 'src/firebase/firestore/field_value.dart';
export 'src/firebase/firestore/filter.dart' show Filter;
export 'src/firebase/firestore/firestore.dart';
export 'src/firebase/firestore/firestore_data_converter.dart';
export 'src/firebase/firestore/firestore_error.dart';
export 'src/firebase/firestore/firestore_settings.dart';
export 'src/firebase/firestore/geo_point.dart';
export 'src/firebase/firestore/listen_source.dart';
export 'src/firebase/firestore/load_bundle_task.dart';
export 'src/firebase/firestore/load_bundle_task_progress.dart';
export 'src/firebase/firestore/log_level.dart' show LogLevel;
export 'src/firebase/firestore/local_cache_settings.dart';
export 'src/firebase/firestore/metadata_change.dart';
export 'src/firebase/firestore/query.dart';
export 'src/firebase/firestore/query_document_snapshot.dart';
export 'src/firebase/firestore/query_snapshot.dart';
export 'src/firebase/firestore/server_timestamp_behavior.dart';
export 'src/firebase/firestore/set_options.dart';
export 'src/firebase/firestore/snapshot_listen_options.dart';
export 'src/firebase/firestore/snapshot_metadata.dart';
export 'src/firebase/firestore/source.dart';
export 'src/firebase/firestore/transaction.dart';
export 'src/firebase/firestore/transaction_options.dart';
export 'src/firebase/firestore/util/database.dart'
    show Database, OnConfigure, OnCreate, OnOpen, OnVersionChange, OpenDatabase;
export 'src/firebase/firestore/vector_query.dart' show VectorQuery;
export 'src/firebase/firestore/vector_query_snapshot.dart';
export 'src/firebase/firestore/vector_value.dart';
export 'src/firebase/firestore/write_batch.dart';
export 'src/firebase/timestamp.dart';
