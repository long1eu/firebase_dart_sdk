// Realtime updates: listen to onConfigUpdated, print the updated keys and
// activate them. Publish a change in the Firebase console while it runs.
//
//     dart run example/realtime.dart --api-key <key> --app-id <id> --project-id <project>
//
// It stops after 5 minutes or at Ctrl-C.

import 'dart:async';
import 'dart:io';

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final FirebaseRemoteConfig remoteConfig = exampleRemoteConfig(arguments);
  final Completer<void> done = Completer<void>();
  final StreamSubscription<RemoteConfigUpdate> subscription = remoteConfig
      .onConfigUpdated
      .listen(
        (RemoteConfigUpdate update) async {
          print('updated keys: ${update.updatedKeys.join(', ')}');
          await remoteConfig.activate();
          for (final String key in update.updatedKeys) {
            print('$key = "${remoteConfig.getString(key)}"');
          }
        },
        onError: (Object error) {
          // The stream keeps going after errors, except realtime-unavailable.
          if (error is FirebaseRemoteConfigException) {
            print('realtime error: ${error.code}: ${error.message}');
          }
        },
        onDone: () {
          if (!done.isCompleted) {
            done.complete();
          }
        },
      );
  final StreamSubscription<ProcessSignal> interrupt = ProcessSignal.sigint
      .watch()
      .listen((ProcessSignal _) {
        if (!done.isCompleted) {
          done.complete();
        }
      });
  try {
    await remoteConfig.fetchAndActivate();
    print('Listening; publish a change in the console.');
    await done.future.timeout(const Duration(minutes: 5), onTimeout: () {});
  } on FirebaseRemoteConfigException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await interrupt.cancel();
    await subscription.cancel();
    await closeAll(remoteConfig);
  }
}
