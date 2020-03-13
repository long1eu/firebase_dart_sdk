// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:typed_data';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

/// Tracks the internal state of a [Watch] target.
class TargetState {
  /// The number of outstanding responses (adds or removes) that we are waiting on. We only consider
  /// targets active that have no outstanding responses.
  int _outstandingResponses = 0;

  /// Keeps track of the document changes since the last raised snapshot.
  ///
  /// These changes are continuously updated as we receive document updates and always reflect the
  /// current set of changes against the last issued snapshot.
  final Map<DocumentKey, DocumentViewChangeType> _documentChanges =
      <DocumentKey, DocumentViewChangeType>{};

  /// Whether this target state should be included in the next snapshot. We initialize to true so
  /// that newly-added targets are included in the next [RemoteEvent].
  bool _hasChanges = true;

  /// The last resume token sent to us for this target.
  Uint8List _resumeToken = Uint8List.fromList(<int>[]);

  bool _current = false;

  /// Whether this target has been marked [_current].
  ///
  /// [_current] has special meaning in the RPC protocol: It implies that the [Watch] backend has
  /// sent us all changes up to the point at which the target was added and that the target is
  /// consistent with the rest of the watch stream.
  bool get isCurrent => _current;

  /// Whether this target has pending target adds or target removes.
  bool isPending() {
    return _outstandingResponses != 0;
  }

  /// Whether we have modified any state that should trigger a snapshot.
  bool get hasChanges => _hasChanges;

  /// Applies the resume token to the [TargetChange], but only when it has a new value. Empty
  /// [resumeTokens] are discarded.
  void updateResumeToken(Uint8List resumeToken) {
    if (resumeToken.isNotEmpty) {
      _hasChanges = true;
      _resumeToken = resumeToken;
    }
  }

  /// Creates a target change from the current set of changes.
  ///
  /// To reset the document changes after raising this snapshot, call [clearChanges].
  TargetChange toTargetChange() {
    ImmutableSortedSet<DocumentKey> addedDocuments = DocumentKey.emptyKeySet;
    ImmutableSortedSet<DocumentKey> modifiedDocuments = DocumentKey.emptyKeySet;
    ImmutableSortedSet<DocumentKey> removedDocuments = DocumentKey.emptyKeySet;

    for (MapEntry<DocumentKey, DocumentViewChangeType> entry
        in _documentChanges.entries) {
      final DocumentKey key = entry.key;
      final DocumentViewChangeType changeType = entry.value;

      if (changeType == DocumentViewChangeType.added) {
        addedDocuments = addedDocuments.insert(key);
      } else if (changeType == DocumentViewChangeType.modified) {
        modifiedDocuments = modifiedDocuments.insert(key);
      } else if (changeType == DocumentViewChangeType.removed) {
        removedDocuments = removedDocuments.insert(key);
      } else {
        throw fail('Encountered invalid change type: $changeType');
      }
    }

    return TargetChange(
      _resumeToken,
      addedDocuments,
      modifiedDocuments,
      removedDocuments,
      current: _current,
    );
  }

  /// Resets the document changes and sets [hasPendingChanges] to false.
  void clearChanges() {
    _hasChanges = false;
    _documentChanges.clear();
  }

  void addDocumentChange(DocumentKey key, DocumentViewChangeType changeType) {
    _hasChanges = true;
    _documentChanges[key] = changeType;
  }

  void removeDocumentChange(DocumentKey key) {
    _hasChanges = true;
    _documentChanges.remove(key);
  }

  void recordPendingTargetRequest() {
    ++_outstandingResponses;
  }

  void recordTargetResponse() {
    --_outstandingResponses;
  }

  void markCurrent() {
    _hasChanges = true;
    _current = true;
  }
}
