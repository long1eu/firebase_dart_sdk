// File created by
// Lung Razvan <long1eu>
// on 28/09/2018
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
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
}
