// File created by
// Lung Razvan <long1eu>
// on 28/09/2018
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;
import 'test_util.dart';

void main() {
  test('testEquals', () {
    final DocumentSnapshot base =
        TestUtil.documentSnapshot('rooms/foo', map(<dynamic>['a', 1]), false);
    final DocumentSnapshot baseDup =
        TestUtil.documentSnapshot('rooms/foo', map(<dynamic>['a', 1]), false);
    final DocumentSnapshot noData =
        TestUtil.documentSnapshot('rooms/foo', null, false);
    final DocumentSnapshot noDataDup =
        TestUtil.documentSnapshot('rooms/foo', null, false);
    final DocumentSnapshot differentPath =
        TestUtil.documentSnapshot('rooms/bar', map(<dynamic>['a', 1]), false);
    final DocumentSnapshot differentData =
        TestUtil.documentSnapshot('rooms/foo', map(<dynamic>['b', 1]), false);
    final DocumentSnapshot fromCache =
        TestUtil.documentSnapshot('rooms/foo', map(<dynamic>['a', 1]), true);

    expect(baseDup, base);
    expect(noDataDup, noData);

    final Matcher notBase = isNot(base);
    expect(noData, notBase);
    expect(base, isNot(noData));
    expect(differentPath, notBase);
    expect(differentData, notBase);
    expect(fromCache, notBase);

    expect(baseDup.hashCode, base.hashCode);
    expect(noDataDup.hashCode, noData.hashCode);
    expect(noData.hashCode, isNot(base.hashCode));
    expect(base.hashCode, isNot(noData.hashCode));
    expect(differentPath.hashCode == base.hashCode, isFalse);
    expect(differentData.hashCode, isNot(base.hashCode));
    expect(fromCache.hashCode, isNot(base.hashCode));
  });
}

// ignore: always_specify_types
const map = util.TestUtil.map;
