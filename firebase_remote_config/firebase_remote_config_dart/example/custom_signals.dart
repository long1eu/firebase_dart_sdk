// Custom signals: set, read back, remove. A change makes the next fetch skip
// the cache, so the server evaluates its conditions on the new signals.
//
// Never put emails, names or account ids in signals: they are stored
// unencrypted and sent on every fetch.
//
//     dart run example/custom_signals.dart --api-key <key> --app-id <id> --project-id <project>

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final FirebaseRemoteConfig remoteConfig = exampleRemoteConfig(arguments);
  try {
    await remoteConfig.setCustomSignals(<String, Object?>{
      'subscription_tier': 'pro',
      'app_build': 412,
      'score': 1.0, // stored as "1"
    });
    print('signals: ${remoteConfig.customSignals}');

    // Sent with the signals, even inside minimumFetchInterval.
    final FetchResult result = await remoteConfig.fetch();
    print('fetch after the change: ${result.name}');

    // null removes a signal.
    await remoteConfig.setCustomSignals(<String, Object?>{'score': null});
    print('signals: ${remoteConfig.customSignals}');

    // Limits are checked before anything is stored.
    try {
      await remoteConfig.setCustomSignals(<String, Object?>{'': 'x'});
    } on ArgumentError catch (e) {
      print('refused: ${e.message}');
    }
  } on FirebaseRemoteConfigException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await closeAll(remoteConfig);
  }
}
