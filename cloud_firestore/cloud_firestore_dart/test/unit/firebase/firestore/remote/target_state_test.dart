// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_state.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Unit tests for [TargetState] (the per-target bookkeeping of the
/// WatchChangeAggregator). The upstream unit tests only cover it indirectly
/// through RemoteEventTest.
void main() {
  test(
      'a new target state has pending changes and is neither current nor '
      'pending', () {
    final TargetState state = TargetState();
    expect(state.hasChanges, isTrue);
    expect(state.isCurrent, isFalse);
    expect(state.isPending(), isFalse);

    final TargetChange change = state.toTargetChange();
    expect(change.current, isFalse);
    expect(change.resumeToken, isEmpty);
    expect(change.addedDocuments, isEmpty);
    expect(change.modifiedDocuments, isEmpty);
    expect(change.removedDocuments, isEmpty);
  });

  test('pending requests are counted', () {
    final TargetState state = TargetState()..recordPendingTargetRequest();
    expect(state.isPending(), isTrue);
    state
      ..recordPendingTargetRequest()
      ..recordTargetResponse();
    expect(state.isPending(), isTrue);
    state.recordTargetResponse();
    expect(state.isPending(), isFalse);
  });

  test('markCurrent sets current and flags changes', () {
    final TargetState state = TargetState()..clearChanges();
    expect(state.hasChanges, isFalse);
    state.markCurrent();
    expect(state.isCurrent, isTrue);
    expect(state.hasChanges, isTrue);
    expect(state.toTargetChange().current, isTrue);
  });

  test('clearChanges drops document changes and the changes flag', () {
    final TargetState state = TargetState()
      ..addDocumentChange(key('c/1'), DocumentViewChangeType.added);
    expect(
        state.toTargetChange().addedDocuments.toList(), <dynamic>[key('c/1')]);

    state.clearChanges();
    expect(state.hasChanges, isFalse);
    expect(state.toTargetChange().addedDocuments, isEmpty);
  });

  test('document changes are partitioned by type', () {
    final TargetState state = TargetState()
      ..addDocumentChange(key('c/1'), DocumentViewChangeType.added)
      ..addDocumentChange(key('c/2'), DocumentViewChangeType.modified)
      ..addDocumentChange(key('c/3'), DocumentViewChangeType.removed);

    final TargetChange change = state.toTargetChange();
    expect(change.addedDocuments.toList(), <dynamic>[key('c/1')]);
    expect(change.modifiedDocuments.toList(), <dynamic>[key('c/2')]);
    expect(change.removedDocuments.toList(), <dynamic>[key('c/3')]);
  });

  test('the latest change for a key wins and removeDocumentChange forgets it',
      () {
    final TargetState state = TargetState()
      ..addDocumentChange(key('c/1'), DocumentViewChangeType.added)
      ..addDocumentChange(key('c/1'), DocumentViewChangeType.modified)
      ..clearChanges()
      ..addDocumentChange(key('c/1'), DocumentViewChangeType.removed);
    expect(state.toTargetChange().removedDocuments.toList(),
        <dynamic>[key('c/1')]);

    state
      ..clearChanges()
      ..addDocumentChange(key('c/2'), DocumentViewChangeType.added)
      ..removeDocumentChange(key('c/2'));
    expect(state.hasChanges, isTrue);
    expect(state.toTargetChange().addedDocuments, isEmpty);
  });

  test('empty resume tokens are discarded, non-empty ones replace', () {
    final TargetState state = TargetState()
      ..clearChanges()
      ..updateResumeToken(Uint8List(0));
    expect(state.hasChanges, isFalse);
    expect(state.toTargetChange().resumeToken, isEmpty);

    state.updateResumeToken(Uint8List.fromList(<int>[1, 2]));
    expect(state.hasChanges, isTrue);
    expect(state.toTargetChange().resumeToken, <int>[1, 2]);

    state.updateResumeToken(Uint8List(0));
    expect(state.toTargetChange().resumeToken, <int>[1, 2]);

    state.updateResumeToken(Uint8List.fromList(<int>[3]));
    expect(state.toTargetChange().resumeToken, <int>[3]);
  });
}
