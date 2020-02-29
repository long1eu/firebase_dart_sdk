// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'package:firebase_common/firebase_common.dart';

/// Represents an internal exception that is thrown to cancel a currently
/// running task.
class CancelException implements Exception {
  CancelException();

  final String message = 'The operation was canceled.';
}
