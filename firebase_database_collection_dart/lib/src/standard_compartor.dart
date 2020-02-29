// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

Comparator<A> standardComparator<A extends Comparable<A>>() {
  return (A a, A b) => a.compareTo(b);
}
