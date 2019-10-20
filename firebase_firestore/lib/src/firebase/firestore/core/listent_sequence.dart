// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

/// Implements a monotonic sequence starting after an initial value.
class ListenSequence {
  ListenSequence(this._previousSequenceNumber);

  static const int invalid = -1;

  int _previousSequenceNumber;

  int get next => ++_previousSequenceNumber;
}
