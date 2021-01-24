// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';

/// Stores the time when the sdk was used and if a sdk heartbeat should be sent for the same.
class SdkHeartBeatResult implements Comparable<SdkHeartBeatResult> {
  const SdkHeartBeatResult(this.sdkName, this.time);

  final String sdkName;
  final DateTime time;

  @override
  int compareTo(SdkHeartBeatResult other) {
    return time.compareTo(other.time);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SdkHeartBeatResult && //
          runtimeType == other.runtimeType &&
          sdkName == other.sdkName &&
          time == other.time;

  @override
  int get hashCode => sdkName.hashCode ^ time.hashCode;

  @override
  String toString() {
    return (ToStringHelper(SdkHeartBeatResult) //
          ..add('sdkName', sdkName)
          ..add('time', time))
        .toString();
  }
}
