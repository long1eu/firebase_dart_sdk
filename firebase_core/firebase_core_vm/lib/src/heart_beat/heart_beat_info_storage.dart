// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'package:firebase_core_vm/platform_dependencies.dart';
import 'package:firebase_core_vm/src/heart_beat/sdk_heart_beat_result.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

/// Class responsible for storing all heartbeat related information.
///
/// This exposes functions to check if there is a need to send global/sdk heartbeat.
/// NOTE: All [DateTime] values are saved in UTC time, and return in local time.
class HeartBeatInfoStorage {
  HeartBeatInfoStorage._(this._storage, this._heartBeatStorage);

  static Future<HeartBeatInfoStorage> getInstance(LocalStorage localStorage) async {
    final LocalStorage storage = await localStorage.getStore(_kStorageKey);
    final LocalStorage heartBeatStorage = await localStorage.getStore(_kStorageStoreKey);

    return _instance ??= HeartBeatInfoStorage._(storage, heartBeatStorage);
  }

  static HeartBeatInfoStorage _instance;

  static const String _kStorageKey = 'FirebaseAppHeartBeat';
  static const String _kStorageStoreKey = 'FirebaseAppHeartBeatStorage';
  static const String _kGlobalKey = '$_kStorageKey-fire-global';
  static const String _kHearBeatCountKey = '$_kStorageKey-fire-count';

  // As soon as you hit the limit of heartbeats. The number of stored heartbeats is halved.
  static const int _kHeartBeatCountLimit = 200;

  static final DateFormat _formatter = DateFormat('dd/MM/yyyy z');

  final LocalStorage _storage;
  final LocalStorage _heartBeatStorage;

  @visibleForTesting
  int get heartBeatCount => _storage.get(_kHearBeatCountKey);

  void storeHeartBeatInformation(String heartBeatTag, DateTime millis) {
    int heartBeatCount = int.parse(_storage.get(_kHearBeatCountKey) ?? '0');

    _heartBeatStorage.set(millis.toUtc().toIso8601String(), heartBeatTag);
    _storage.set(_kHearBeatCountKey, '${heartBeatCount + 1}');

    heartBeatCount += 1;
    if (heartBeatCount > _kHeartBeatCountLimit) {
      _cleanUpStoredHeartBeats();
    }
  }

  void _cleanUpStoredHeartBeats() {
    int heartBeatCount = int.parse(_storage.get(_kHearBeatCountKey) ?? '0');

    final List<DateTime> timestampList = _heartBeatStorage.keys.map(DateTime.parse).toList()..sort();
    for (DateTime date in timestampList) {
      _heartBeatStorage.set(date.toIso8601String(), null);
      _storage.set(_kHearBeatCountKey, '${heartBeatCount - 1}');

      heartBeatCount -= 1;
      if (heartBeatCount <= (_kHeartBeatCountLimit / 2)) {
        return;
      }
    }
  }

  DateTime get lastGlobalHeartBeat {
    final String date = _storage.get(_kGlobalKey);
    if (date == null) {
      return null;
    }

    return DateTime.parse(date).toLocal();
  }

  set lastGlobalHeartBeat(DateTime time) {
    time = time.toUtc();
    _storage.set(_kGlobalKey, time.toIso8601String());
  }

  List<SdkHeartBeatResult> getStoredHeartBeats(bool shouldClear) {
    final List<SdkHeartBeatResult> sdkHeartBeatResults = _heartBeatStorage.keys
        .map((String key) => SdkHeartBeatResult(_heartBeatStorage.get(key), DateTime.parse(key).toLocal()))
        .toList()
          ..sort();

    if (shouldClear) {
      clearStoredHeartBeats();
    }
    return sdkHeartBeatResults;
  }

  void clearStoredHeartBeats() {
    for (String key in _heartBeatStorage.keys.where((String key) => key.startsWith(_kStorageStoreKey))) {
      _heartBeatStorage.set(key, null);
    }
    _storage.set(_kHearBeatCountKey, null);
  }

  static bool isSameDateUtc(DateTime base, DateTime target) {
    return _formatter.format(base) == _formatter.format(target);
  }

  /*
   Indicates whether or not we have to send a sdk heartbeat.
   A sdk heartbeat is sent either when there is no heartbeat sent ever for the sdk or
   when the last heartbeat send for the sdk was later than a day before.
  */
  bool shouldSendSdkHeartBeat(String heartBeatTag, DateTime millis) {
    millis = millis.toUtc();
    final DateTime value = DateTime.tryParse(_storage.get(heartBeatTag));
    if (value != null) {
      if (isSameDateUtc(value, millis)) {
        _storage.set(heartBeatTag, millis.toIso8601String());
        return true;
      }
      return false;
    } else {
      _storage.set(heartBeatTag, millis.toIso8601String());
      return true;
    }
  }

  /*
   Indicates whether or not we have to send a global heartbeat.
   A global heartbeat is set only once per day.
  */
  bool shouldSendGlobalHeartBeat(DateTime time) {
    return shouldSendSdkHeartBeat(_kGlobalKey, time);
  }
}
