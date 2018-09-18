// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'package:firebase_common/src/annotations.dart';
import 'package:firebase_common/src/util/to_string_helper.dart';

/// Represents an internal token result.
@keepForSdk
class InternalTokenResult {
  @keepForSdk
  final String token;

  @keepForSdk
  const InternalTokenResult(this.token);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InternalTokenResult &&
          runtimeType == other.runtimeType &&
          token == other.token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)..add('token', token)).toString();
  }
}
