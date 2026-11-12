import 'package:test/test.dart';

import '../../util/comparator_test.dart';

class _Loose implements Comparable<_Loose> {
  _Loose(this.v, this.tag);
  final int v;
  final int tag;
  @override
  int compareTo(_Loose other) => v.compareTo(other.v);
  @override
  bool operator ==(Object other) => other is _Loose && other.tag == tag;
  @override
  int get hashCode => tag;
}

void main() {
  test('consistent natural ordering passes with several groups', () {
    ComparatorTester<int>()
        .addItem(1)
        .addItem(2)
        .addEqualityGroup(<int>[3, 3]).testCompare();
  });

  test('equal-compare items that are not == fail by default', () {
    expect(
        () => ComparatorTester<_Loose>().addEqualityGroup(
            <_Loose>[_Loose(1, 1), _Loose(1, 2)]).testCompare(),
        throwsA(isA<TestFailure>()));
  });

  test('== across groups fails by default', () {
    expect(
        () => ComparatorTester<_Loose>()
            .addItem(_Loose(1, 7))
            .addItem(_Loose(2, 7))
            .testCompare(),
        throwsA(isA<TestFailure>()));
  });

  test('permitInconsistencyWithEquals skips the check', () {
    ComparatorTester<_Loose>()
        .permitInconsistencyWithEquals()
        .addEqualityGroup(<_Loose>[_Loose(1, 1), _Loose(1, 2)]).testCompare();
  });

  test('a comparator tester does not check equals unless asked', () {
    ComparatorTester<int>((int a, int b) => (a ~/ 10).compareTo(b ~/ 10))
        .addEqualityGroup(<int>[1, 2]).addEqualityGroup(
            <int>[11]).testCompare();
  });
}
