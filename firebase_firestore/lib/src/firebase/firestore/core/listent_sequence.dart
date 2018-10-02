// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

/// Implements a monotonic sequence starting after an initial value.
class ListenSequence {
  static const int invalid = -1;

  int previousSequenceNumber;

  ListenSequence(this.previousSequenceNumber);

  int next() => ++previousSequenceNumber;
}
