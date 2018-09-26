// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:firebase_common/firebase_common.dart';

/// Represents a listener that can be removed by calling remove().
@publicApi
abstract class ListenerRegistration {
  /// Removes the listener being tracked by this [ListenerRegistration]. After
  /// the initial call, subsequent calls have no effect.
  @publicApi
  void remove();
}
