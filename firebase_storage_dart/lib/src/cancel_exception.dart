// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'package:firebase_core/firebase_core.dart';

/// Represents an internal exception that is thrown to cancel a currently
/// running task.
class CancelException implements Exception {
  CancelException();

  final String message = 'The operation was canceled.';
}
