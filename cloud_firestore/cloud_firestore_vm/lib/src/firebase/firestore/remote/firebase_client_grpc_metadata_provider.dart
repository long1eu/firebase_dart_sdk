// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:meta/meta.dart';

typedef GrpcMetadataProvider = Future<void> Function(Map<String, String> metadata);

/// Provides an implementation of the GrpcMetadataProvider interface.
///
/// This updates the metadata with platformInfo string and the heartBeatInfo code.
class FirebaseClientGrpcMetadataProvider {
  FirebaseClientGrpcMetadataProvider({
    @required HeartBeatInfo heartBeatInfo,
    @required FirebaseOptions firebaseOptions,
    UserAgentPublisher userAgentPublisher,
  })  : _heartBeatInfo = heartBeatInfo,
        _firebaseOptions = firebaseOptions,
        _userAgentPublisher = userAgentPublisher ?? UserAgentPublisher.instance;

  final HeartBeatInfo _heartBeatInfo;
  final UserAgentPublisher _userAgentPublisher;
  final FirebaseOptions _firebaseOptions;

  static const String _kHeartBeatKey = 'fire-fst';
  static const String _kHeartBeatHeader = 'x-firebase-client-log-type';
  static const String _kUserAgentHeader = 'x-firebase-client';
  static const String _kGmpAppIdHeader = 'x-firebase-gmpid';

  Future<void> call(Map<String, String> metadata) async {
    if (_heartBeatInfo == null || _userAgentPublisher == null) {
      return;
    }

    final int heartBeatCode = _heartBeatInfo.getHeartBeatCode(_kHeartBeatKey).code;
    // Non-zero values indicate some kind of heartbeat should be sent.
    if (heartBeatCode != 0) {
      metadata[_kHeartBeatHeader] = '$heartBeatCode';
    }

    metadata[_kUserAgentHeader] = _userAgentPublisher.userAgent;
    _maybeAddGmpAppId(metadata);
  }

  void _maybeAddGmpAppId(Map<String, String> metadata) {
    if (_firebaseOptions == null) {
      return;
    }

    final String gmpAppId = _firebaseOptions.appId;
    if (gmpAppId.isNotEmpty) {
      metadata[_kGmpAppIdHeader] = gmpAppId;
    }
  }
}
