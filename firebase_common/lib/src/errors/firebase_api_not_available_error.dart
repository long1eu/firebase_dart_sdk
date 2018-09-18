// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'package:firebase_common/src/annotations.dart';
import 'package:firebase_common/src/errors/firebase_error.dart';

@publicApi
class FirebaseApiNotAvailableError extends FirebaseError {
  @publicApi
  const FirebaseApiNotAvailableError(String message) : super(message);
}
