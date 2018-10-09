// File created by
// Lung Razvan <long1eu>
// on 28/09/2018
import 'package:firebase_firestore/src/firebase/firestore/snapshot_metadata.dart';
import 'package:test/test.dart';

void main() {
  test('testEquals', () {
    const SnapshotMetadata foo = const SnapshotMetadata(true, true);
    const SnapshotMetadata fooDup = const SnapshotMetadata(true, true);
    const SnapshotMetadata bar = const SnapshotMetadata(true, false);
    const SnapshotMetadata baz = const SnapshotMetadata(false, true);

    expect(fooDup, foo);
    expect(bar, isNot(foo));
    expect(baz, isNot(foo));
    expect(baz, isNot(bar));

    expect(fooDup.hashCode, foo.hashCode);
    expect(bar.hashCode, isNot(foo.hashCode));
    expect(baz.hashCode, isNot(foo.hashCode));
    expect(baz.hashCode, isNot(bar.hashCode));
  });
}
