// File created by
// Lung Razvan <long1eu>
// on 28/09/2018
import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;
import 'test_util.dart';

void main() {
  test('testEquals', () {
    final DocumentSnapshot base =
        documentSnapshot('rooms/foo', util.map(<dynamic>['a', 1]), false);
    final DocumentSnapshot baseDup =
        documentSnapshot('rooms/foo', util.map(<dynamic>['a', 1]), false);
    final DocumentSnapshot noData = documentSnapshot('rooms/foo', null, false);
    final DocumentSnapshot noDataDup =
        documentSnapshot('rooms/foo', null, false);
    final DocumentSnapshot differentPath =
        documentSnapshot('rooms/bar', util.map(<dynamic>['a', 1]), false);
    final DocumentSnapshot differentData =
        documentSnapshot('rooms/foo', util.map(<dynamic>['b', 1]), false);
    final DocumentSnapshot fromCache =
        documentSnapshot('rooms/foo', util.map(<dynamic>['a', 1]), true);

    expect(baseDup, base);
    expect(noDataDup, noData);

    final Matcher notBase = isNot(base);
    expect(noData, notBase);
    expect(base, isNot(noData));
    expect(differentPath, notBase);
    expect(differentData, notBase);
    expect(fromCache, notBase);

    // The assertions below that hash codes of different values are not equal is
    // not something that we guarantee. In particular [base] and [differentData]
    // have a hash collision because we don't use data in the hashCode.
    expect(baseDup.hashCode, base.hashCode);
    expect(noDataDup.hashCode, noData.hashCode);
    expect(noData.hashCode, isNot(base.hashCode));
    expect(base.hashCode, isNot(noData.hashCode));
    expect(differentPath.hashCode == base.hashCode, isFalse);
    expect(fromCache.hashCode, isNot(base.hashCode));
  });

  test('testEqualsIgnoresDocumentStateAndVersion', () {
    // Only the key, the metadata and the data are compared. The internal state
    // of the underlying document (its version, whether it has local mutations)
    // does not matter.
    DocumentSnapshot snapshot(int version, DocumentState state) {
      return DocumentSnapshotInternal.fromDocument(
        firestore,
        util.doc(
            'rooms/foo', version, util.map<Object>(<dynamic>['a', 1]), state),
        isFromCache: false,
        hasPendingWrites: false,
      );
    }

    final DocumentSnapshot base = snapshot(1, DocumentState.synced);
    final DocumentSnapshot otherVersion = snapshot(2, DocumentState.synced);
    final DocumentSnapshot otherState =
        snapshot(1, DocumentState.committedMutations);

    expect(otherVersion, base);
    expect(otherState, base);
    expect(otherVersion.hashCode, base.hashCode);
    expect(otherState.hashCode, base.hashCode);

    final DocumentSnapshot differentData = DocumentSnapshotInternal.fromDocument(
      firestore,
      util.doc('rooms/foo', 1, util.map<Object>(<dynamic>['a', 2])),
      isFromCache: false,
      hasPendingWrites: false,
    );
    expect(differentData, isNot(base));
  });

  // firebase-js-sdk #10250: the warning names the referenced document, not
  // the document that contains the reference.
  test('a reference to another database is logged with the referenced key', () {
    final DocumentSnapshot<Map<String, Object?>> snapshot =
        DocumentSnapshotInternal.fromDocument(
          firestore,
          Document(
            util.key('rooms/holder'),
            util.version(1),
            DocumentState.synced,
            ObjectValue.fromMap(<String, FieldValue>{
              'ref': ReferenceValue.valueOf(
                DatabaseId.forDatabase('other-project', 'other-db'),
                util.key('rooms/target'),
              ),
            }),
          ),
          isFromCache: false,
          hasPendingWrites: false,
        );

    final List<String> logs = <String>[];
    runZoned(
      () => snapshot.data,
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, String line) => logs.add(line),
      ),
    );

    expect(logs, hasLength(1));
    expect(
      logs.single,
      contains(
        'A document reference to rooms/target refers to a different '
        'database (other-project/other-db), which is not supported.',
      ),
    );
    expect(logs.single, isNot(contains('rooms/holder')));
  });
}
