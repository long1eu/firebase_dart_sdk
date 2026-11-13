/// Firestore Lite: a Cloud Firestore client without a local cache, without
/// listeners and without the sync engine. Every call is one request to the
/// backend and one response, over gRPC on native platforms and over REST on
/// the web. It is the Dart counterpart of `firebase/firestore/lite` of the JS
/// SDK.
///
/// **Experimental**: this API may change in any release.
///
/// ```dart
/// import 'package:cloud_firestore_dart/lite.dart';
///
/// final Firestore firestore = Firestore.instanceFor(app: app);
/// await firestore.doc('cities/SF').set({'name': 'San Francisco'});
/// final QuerySnapshot<Map<String, Object?>> cities = await firestore
///     .collection('cities')
///     .where('name', isEqualTo: 'San Francisco')
///     .get();
/// ```
///
/// Import this library *instead of* `cloud_firestore_dart.dart`: both declare
/// `Firestore`, `DocumentReference`, `Query` and the snapshot classes (import
/// one of them with a prefix to use both in one file). The value types
/// (`Timestamp`, `GeoPoint`, `Blob`, `FieldValue`, `FieldPath`, `Filter`, ...)
/// are the same classes in both libraries.
///
/// A program that only imports this library does not contain the sync engine,
/// the local store or the SQLite layer of the main library.
library cloud_firestore_dart.lite;

export 'src/firebase/firestore/aggregate_field.dart'
    hide AggregateFieldInternal;
export 'src/firebase/firestore/blob.dart';
export 'src/firebase/firestore/bson_object_id.dart';
export 'src/firebase/firestore/bson_timestamp.dart';
export 'src/firebase/firestore/decimal128_value.dart';
export 'src/firebase/firestore/field_path.dart' hide FieldPathInternal;
export 'src/firebase/firestore/field_value.dart' hide FieldValueInternal;
export 'src/firebase/firestore/filter.dart' show Filter;
export 'src/firebase/firestore/firestore_error.dart';
export 'src/firebase/firestore/geo_point.dart';
export 'src/firebase/firestore/int32_value.dart';
export 'src/firebase/firestore/lite/aggregate.dart';
export 'src/firebase/firestore/lite/data_converter.dart' hide toRawData;
export 'src/firebase/firestore/lite/document_reference.dart';
export 'src/firebase/firestore/lite/firestore.dart' hide liteTransportOverride;
export 'src/firebase/firestore/lite/query.dart';
export 'src/firebase/firestore/lite/settings.dart';
export 'src/firebase/firestore/lite/snapshot.dart';
export 'src/firebase/firestore/lite/transaction.dart';
export 'src/firebase/firestore/lite/write_batch.dart';
export 'src/firebase/firestore/log_level.dart' show LogLevel;
export 'src/firebase/firestore/max_key.dart';
export 'src/firebase/firestore/min_key.dart';
export 'src/firebase/firestore/query.dart' show Direction;
export 'src/firebase/firestore/regex_value.dart';
export 'src/firebase/firestore/set_options.dart' hide SetOptionsInternal;
export 'src/firebase/firestore/transaction_options.dart';
export 'src/firebase/firestore/vector_value.dart';
export 'src/firebase/timestamp.dart' hide TimestampInternal;
