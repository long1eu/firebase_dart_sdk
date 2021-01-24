// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'heart_beat_result.dart';

/// Class provides information about heartbeats.
///
/// This exposes a function which returns the [HeartBeatCode]. If both sdk heartbeat and global
/// heartbeat needs to sent then [HeartBeat.combined] is returned. If only sdk heart beat needs to be
/// sent then [HeartBeat.sdk] is returned. If only global heart beat needs to be sent then
/// [HeartBeat.global] is returned. If no heart beat needs to be sent then [HeartBeat.none] is returned.
///
/// This also exposes functions to store and retrieve [HeartBeatInfo] in the form of
/// [HeartBeatResult].
abstract class HeartBeatInfo {
  HeartBeat getHeartBeatCode(String heartBeatTag);

  Future<void> storeHeartBeatInfo(String heartBeatTag);

  Future<List<HeartBeatResult>> getAndClearStoredHeartBeatInfo();
}

class HeartBeat {
  const HeartBeat._(this.code);

  final int code;

  static const HeartBeat none = HeartBeat._(0);
  static const HeartBeat sdk = HeartBeat._(1);
  static const HeartBeat global = HeartBeat._(2);
  static const HeartBeat combined = HeartBeat._(3);

  List<HeartBeat> get values => <HeartBeat>[none, sdk, global, combined];

  List<String> get _names => <String>['none', 'sdk', 'global', 'combined'];

  @override
  String toString() {
    return 'HearBeat.${_names[code]}';
  }
}
