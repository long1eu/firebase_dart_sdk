/// An unofficial, pure-Dart client of Cloud Storage for Firebase.
///
/// Create a [FirebaseStorage] for a `FirebaseApp`, get a [Reference] with [FirebaseStorage.ref], and read,
/// write, list and delete objects through it. Errors are [FirebaseStorageException]s.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
/// import 'package:firebase_storage_dart/firebase_storage_dart.dart';
///
/// Future<void> main() async {
///   final FirebaseApp app = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<the Web API key of the project>',
///       appId: '1:1234567890:dart:example',
///       projectId: 'my-project',
///       storageBucket: 'my-project.appspot.com',
///     ),
///   );
///   final FirebaseStorage storage = FirebaseStorage(app);
///   final ListResult page = await storage.ref('photos').list(maxResults: 10);
///   for (final Reference item in page.items) {
///     print(item.fullPath);
///   }
///   storage.close();
/// }
/// ```
library;

// Imported for the references in the documentation above.
import 'src/exception.dart';
import 'src/firebase_storage.dart';
import 'src/reference.dart';

export 'src/exception.dart';
export 'src/firebase_storage.dart';
export 'src/list_result.dart';
export 'src/metadata.dart' show FullMetadata, MetadataField, SettableMetadata;
export 'src/reference.dart';
export 'src/retry_policy.dart';
export 'src/string_format.dart' show StringFormat;
export 'src/upload/upload_task.dart'
    show UploadProgress, UploadState, UploadTask;
