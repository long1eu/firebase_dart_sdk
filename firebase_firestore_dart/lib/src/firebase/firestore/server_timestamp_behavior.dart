// File created by
// Lung Razvan <long1eu>
// on 17/09/2018
import 'package:firebase_common/firebase_common.dart';

/// Controls the return value for server timestamps that have not yet been set to their final value.
enum ServerTimestampBehavior {
  /// Return 'null' for [FieldValue.serverTimestampServerTimestamps] that have not yet been set to
  /// their final value.
  none,

  /// Return local estimates for [FieldValue.serverTimestampServerTimestamps] that have not yet been
  /// set to their final value. This estimate will likely differ from the final value and may cause
  /// these pending values to change once the server result becomes available.
  estimate,

  /// Return the previous value for [FieldValue.serverTimestampServerTimestamps] that have not yet
  /// been set to their final value.
  previous,
}
