// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:meta/meta.dart';

/// The kind of change a [DocumentChange] describes.
enum DocumentChangeType {
  /// Indicates a new document was added to the set of documents matching the query.
  added,

  /// Indicates a document within the query was modified.
  modified,

  /// Indicates a document within the query was removed (either deleted or no  longer matches the
  /// query.
  removed
}

/// A [DocumentChange] represents a change to the documents matching a query. It contains the
/// document affected and a the type of change that occurred (added, modified, or removed).
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class DocumentChange<T extends dynamic> {
  /// Implementation detail of the SDK; not part of the supported API.
  @visibleForTesting
  @internal
  DocumentChange(this.document, this.type, this.oldIndex, this.newIndex);

  /// An enumeration of snapshot diff types.
  final DocumentChangeType type;

  /// Returns the newly added or modified document if this [DocumentChange] is for an updated
  /// document. Returns the deleted document if this document change represents a removal.
  ///
  /// Returns a snapshot of the new data (for [DocumentChangeType.added] or
  /// [DocumentChangeType.modified]) or the removed data (for [DocumentChangeType.removed]).
  final QueryDocumentSnapshot<T> document;

  /// The index of the changed document in the result set immediately prior to this [DocumentChange]
  /// (i.e. supposing that all prior [DocumentChange] objects have been applied). Returns -1 for
  /// 'added' events.
  ///
  /// Returns the index in the old snapshot, after processing all previous changes.
  final int oldIndex;

  /// The index of the changed document in the result set immediately after this [DocumentChange]
  /// (i.e. supposing that all prior [DocumentChange] objects and the current [DocumentChange]
  /// object have been applied). Returns -1 for 'removed' events.
  ///
  /// The index in the new snapshot, after processing all previous changes.
  final int newIndex;

  /// Creates the list of DocumentChanges from a ViewSnapshot.
  @internal
  static List<DocumentChange<T>> changesFromSnapshot<T extends Object?>(
      Firestore firestore, MetadataChanges metadataChanges, ViewSnapshot snapshot,
      [FirestoreDataConverter<T>? converter]) {
    final List<DocumentChange<T>> documentChanges = <DocumentChange<T>>[];
    if (snapshot.oldDocuments.isEmpty) {
      // Special case the first snapshot because index calculation is easy and fast. Also all
      // changes on the first snapshot are adds so there are also no metadata-only changes to filter
      // out.
      int index = 0;
      Document? lastDoc;
      for (DocumentViewChange change in snapshot.changes) {
        final Document document = change.document;
        final QueryDocumentSnapshot<T> documentSnapshot =
            QueryDocumentSnapshot<T>.fromDocument(
          firestore,
          document,
          fromCache: snapshot.isFromCache,
          hasPendingWrites: snapshot.mutatedKeys.contains(document.key),
          converter: converter,
        );

        hardAssert(change.type == DocumentViewChangeType.added,
            'Invalid added event for first snapshot');
        hardAssert(
            lastDoc == null || snapshot.query.comparator(lastDoc, document) < 0,
            'Got added events in wrong order');
        documentChanges.add(DocumentChange<T>(
            documentSnapshot, DocumentChangeType.added, -1, index++));
        lastDoc = document;
      }
    } else {
      // A DocumentSet that is updated incrementally as changes are applied to use to lookup the
      // index of a document.
      DocumentSet indexTracker = snapshot.oldDocuments;
      for (DocumentViewChange change in snapshot.changes) {
        if (metadataChanges == MetadataChanges.exclude &&
            change.type == DocumentViewChangeType.metadata) {
          continue;
        }
        final Document document = change.document;
        final QueryDocumentSnapshot<T> documentSnapshot =
            QueryDocumentSnapshot<T>.fromDocument(
          firestore,
          document,
          fromCache: snapshot.isFromCache,
          hasPendingWrites: snapshot.mutatedKeys.contains(document.key),
          converter: converter,
        );
        int oldIndex, newIndex;
        final DocumentChangeType type = _getType(change);
        if (type != DocumentChangeType.added) {
          oldIndex = indexTracker.indexOf(document.key);
          hardAssert(oldIndex >= 0, 'Index for document not found');
          indexTracker = indexTracker.remove(document.key);
        } else {
          oldIndex = -1;
        }
        if (type != DocumentChangeType.removed) {
          indexTracker = indexTracker.add(document);
          newIndex = indexTracker.indexOf(document.key);
          hardAssert(newIndex >= 0, 'Index for document not found');
        } else {
          newIndex = -1;
        }
        documentChanges
            .add(DocumentChange<T>(documentSnapshot, type, oldIndex, newIndex));
      }
    }
    return documentChanges;
  }

  static DocumentChangeType _getType(DocumentViewChange change) {
    if (change.type == DocumentViewChangeType.added) {
      return DocumentChangeType.added;
    } else if (change.type == DocumentViewChangeType.modified ||
        change.type == DocumentViewChangeType.metadata) {
      return DocumentChangeType.modified;
    } else if (change.type == DocumentViewChangeType.removed) {
      return DocumentChangeType.removed;
    } else {
      throw ArgumentError('Unknown view change type: ${change.type}');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentChange &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          document == other.document &&
          oldIndex == other.oldIndex &&
          newIndex == other.newIndex;

  @override
  int get hashCode =>
      type.hashCode ^ document.hashCode ^ oldIndex.hashCode ^ newIndex.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('type', type)
          ..add('document', document)
          ..add('oldIndex', oldIndex)
          ..add('newIndex', newIndex))
        .toString();
  }
}
