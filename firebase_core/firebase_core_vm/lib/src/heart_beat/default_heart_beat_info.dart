// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'package:firebase_core_vm/platform_dependencies.dart';
import 'package:firebase_core_vm/src/heart_beat/heart_beat_info.dart';
import 'package:firebase_core_vm/src/heart_beat/heart_beat_info_storage.dart';
import 'package:firebase_core_vm/src/heart_beat/heart_beat_result.dart';
import 'package:firebase_core_vm/src/heart_beat/sdk_heart_beat_result.dart';

/// Provides information as whether to send heart beat or not.
class DefaultHeartBeatInfo implements HeartBeatInfo {
  DefaultHeartBeatInfo._(this._storage);

  Future<DefaultHeartBeatInfo> create(LocalStorage storage) async {
    final HeartBeatInfoStorage _storage = await HeartBeatInfoStorage.getInstance(storage);
    return DefaultHeartBeatInfo._(_storage);
  }

  final HeartBeatInfoStorage _storage;

  @override
  Future<List<HeartBeatResult>> getAndClearStoredHeartBeatInfo() async {
    final List<HeartBeatResult> heartBeatResults = <HeartBeatResult>[];
    bool shouldSendGlobalHeartBeat = false;

    final List<SdkHeartBeatResult> sdkHeartBeatResults = _storage.getStoredHeartBeats(true);
    DateTime lastGlobalHeartBeat = _storage.lastGlobalHeartBeat;
    HeartBeat heartBeat;
    for (final SdkHeartBeatResult sdkHeartBeatResult in sdkHeartBeatResults) {
      shouldSendGlobalHeartBeat = HeartBeatInfoStorage.isSameDateUtc(lastGlobalHeartBeat, sdkHeartBeatResult.time);
      if (shouldSendGlobalHeartBeat) {
        heartBeat = HeartBeat.combined;
      } else {
        heartBeat = HeartBeat.sdk;
      }
      if (shouldSendGlobalHeartBeat) {
        lastGlobalHeartBeat = sdkHeartBeatResult.time;
      }
      heartBeatResults.add(HeartBeatResult(sdkHeartBeatResult.sdkName, sdkHeartBeatResult.time, heartBeat));
    }
    if (lastGlobalHeartBeat != null) {
      _storage.lastGlobalHeartBeat = lastGlobalHeartBeat;
    }
    return heartBeatResults;
  }

  @override
  HeartBeat getHeartBeatCode(String heartBeatTag) {
    final DateTime presentTime = DateTime.now();
    final bool shouldSendSdkHB = _storage.shouldSendSdkHeartBeat(heartBeatTag, presentTime);
    final bool shouldSendGlobalHB = _storage.shouldSendGlobalHeartBeat(presentTime);
    if (shouldSendSdkHB && shouldSendGlobalHB) {
      return HeartBeat.combined;
    } else if (shouldSendGlobalHB) {
      return HeartBeat.global;
    } else if (shouldSendSdkHB) {
      return HeartBeat.sdk;
    }
    return HeartBeat.none;
  }

  @override
  Future<void> storeHeartBeatInfo(String heartBeatTag) async {
    final DateTime presentTime = DateTime.now();
    final bool shouldSendSdkHB = _storage.shouldSendSdkHeartBeat(heartBeatTag, presentTime);
    if (shouldSendSdkHB) {
      _storage.storeHeartBeatInformation(heartBeatTag, presentTime);
    }
  }
}
