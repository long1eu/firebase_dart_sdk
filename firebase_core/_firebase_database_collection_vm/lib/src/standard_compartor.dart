// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

// Shared instance so that maps built with standardComparator() compare equal.
int _compare(dynamic a, dynamic b) => (a as Comparable<dynamic>).compareTo(b);

Comparator<A> standardComparator<A extends Comparable<A>>() => _compare;

/// The natural ordering of [T], shared so that collections built without an
/// explicit comparator compare equal (comparators are compared by identity).
Comparator<T> naturalComparator<T>() => _compare;
