// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';

/// Simple wrapper around a nullable UID. Mostly exists to make code more
/// readable and for use as a key in maps (since keys cannot be null).
class User {
  static const User unauthenticated = const User();

  // Porting note: no GOOGLE_CREDENTIALS or FIRST_PARTY on Android, see Token
  // for more details.
  final String uid;

  const User([this.uid]);

  bool get isAuthenticated => uid != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User && runtimeType == other.runtimeType && uid == other.uid;

  @override
  int get hashCode => uid.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
      ..add('uid', uid)).toString();
  }
}
