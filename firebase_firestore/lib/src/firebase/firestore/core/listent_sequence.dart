// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

/// Implements a monotonic sequence starting after an initial value.
class ListenSequence {
  static const int INVALID = -1;

  int previousSequenceNumber;

  ListenSequence(int this.previousSequenceNumber);

  int next() => ++previousSequenceNumber;
}
