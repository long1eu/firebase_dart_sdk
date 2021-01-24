// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';

import 'heart_beat_info.dart';

/// Stores the information about when the sdk was used and what kind of heartbeat needs to be sent
/// for the same.
class HeartBeatResult {
  const HeartBeatResult(this.sdkName, this.time, this.heartBeat);

  final String sdkName;
  final DateTime time;
  final HeartBeat heartBeat;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeartBeatResult && //
          runtimeType == other.runtimeType &&
          sdkName == other.sdkName &&
          time == other.time &&
          heartBeat == other.heartBeat;

  @override
  int get hashCode => sdkName.hashCode ^ time.hashCode ^ heartBeat.hashCode;

  @override
  String toString() {
    return (ToStringHelper(HeartBeatResult)
          ..add('sdkName', sdkName)
          ..add('time', time)
          ..add('heartBeat', heartBeat))
        .toString();
  }
}
