// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:grpc/src/shared/status.dart';

class Util {
  static String toDebugString(List<int> bytes) {
    final int size = bytes.length;
    StringBuffer result = StringBuffer(2 * size);
    for (int i = 0; i < size; i++) {
      final int value = bytes[i] & 0xFF;

      result.write((value >> 4).toRadixString(16));
      result.write((value & 0xF).toRadixString(16));
    }
    return result.toString();
  }

  static int compareBools(bool b1, bool b2) {
    if (b1 == b2) {
      return 0;
    } else if (b1) {
      return 1;
    } else {
      return -1;
    }
  }

  static FirebaseFirestoreError exceptionFromStatus(GrpcError error) {
    return new FirebaseFirestoreError(
        error.message, FirebaseFirestoreErrorCode.values[error.code]);
  }
}
