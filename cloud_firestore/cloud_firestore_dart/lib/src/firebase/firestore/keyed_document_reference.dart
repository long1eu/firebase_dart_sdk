import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';

/// What the value parser needs to know about a document reference that is not
/// the `DocumentReference` of the main library: the reference class of
/// Firestore Lite implements this, so that the parser does not depend on it.
abstract class KeyedDocumentReference {
  /// The key of the document.
  DocumentKey get key;

  /// The database the document is in.
  DatabaseId get databaseId;
}
