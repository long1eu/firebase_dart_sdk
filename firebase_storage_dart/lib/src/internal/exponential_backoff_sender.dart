// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage_vm/src/internal/util.dart';
import 'package:firebase_storage_vm/src/network/network_request.dart';

/// This is a Network request sender that uses exponential backoff, but also
/// retries without backoff if the network is unavailable in the client and
/// instead uses simple polling. In both cases, the retry time is capped by a
/// setting which if exceeded will result in the task failing.
class ExponentialBackoffSender {
  ExponentialBackoffSender(this._app, this._retryTime);

  static const String _tag = 'ExponenentialBackoff';

  static const int kRndMax = 250;
  static const int _kNetworkStatusPollInterval = 1000;
  static const int _kMaximumWaitTimeMs = 30000;
  static final Random _random = Random();

  final FirebaseApp _app;
  final Duration _retryTime;

  bool _canceled = false;

  bool isRetryableError(int resultCode) {
    return (resultCode >= 500 && resultCode < 600) ||
        resultCode == kNetworkUnavailable ||
        resultCode == 429 ||
        resultCode == 408;
  }

  Future<void> sendWithExponentialBackoff(NetworkRequest request,
      {final bool closeRequest = true}) async {
    Preconditions.checkNotNull(request);
    final int deadLine =
        DateTime.now().millisecondsSinceEpoch + _retryTime.inMilliseconds;
    final String authToken = await getCurrentAuthToken(_app);
    if (closeRequest) {
      await request.performRequest(authToken);
    } else {
      await request.performRequestStart(authToken);
    }

    int currentSleepTime = _kNetworkStatusPollInterval;
    while (
        DateTime.now().millisecondsSinceEpoch + currentSleepTime <= deadLine &&
            !request.isResultSuccess &&
            isRetryableError(request.resultCode)) {
      try {
        await Future<void>.delayed(Duration(
            milliseconds: currentSleepTime + _random.nextInt(kRndMax)));
      } catch (e) {
        Log.w(_tag, 'Task interrupted during exponential backoff.');

        //todo this below
        Isolate.current.kill();
        return;
      }

      if (currentSleepTime < _kMaximumWaitTimeMs) {
        if (request.resultCode != kNetworkUnavailable) {
          currentSleepTime = currentSleepTime * 2;
          Log.w(_tag, 'network error occurred, backing off/sleeping.');
        } else {
          currentSleepTime = _kNetworkStatusPollInterval;
          Log.w(_tag, 'network unavailable, sleeping.');
        }
      }

      if (_canceled) {
        return;
      }
      request.reset();
      final String authToken = await getCurrentAuthToken(_app);

      if (closeRequest) {
        await request.performRequest(authToken);
      } else {
        await request.performRequestStart(authToken);
      }
    }
  }

  void cancel() => _canceled = true;

  void reset() => _canceled = false;
}
