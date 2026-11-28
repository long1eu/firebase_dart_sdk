// fetch() and activate() as two steps, the FetchResult of each fetch, and the
// RemoteConfigInfo after them.
//
//     dart run example/fetch_and_activate.dart --api-key <key> --app-id <id> --project-id <project>

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final FirebaseRemoteConfig remoteConfig = exampleRemoteConfig(arguments);
  try {
    // The first fetch reaches the server: updated or unchanged.
    final FetchResult first = await remoteConfig.fetch();
    print('first fetch: ${first.name}');
    // Within minimumFetchInterval (12 hours by default) the next one is
    // answered from the stored template, without a request.
    final FetchResult second = await remoteConfig.fetch();
    print('second fetch: ${second.name}');

    // Reads still use the defaults until the fetched template is activated.
    final bool activated = await remoteConfig.activate();
    print('activated: $activated');
    for (final MapEntry<String, RemoteConfigValue> entry
        in remoteConfig.getAll().entries) {
      print(
        '${entry.key} = "${entry.value.asString()}" '
        '(${entry.value.source.name})',
      );
    }

    final RemoteConfigInfo info = remoteConfig.info;
    print(
      'status: ${info.lastFetchStatus.name}, '
      'fetched at ${info.lastSuccessfulFetchTime}, '
      'template version ${info.activeTemplateVersion}',
    );
  } on FirebaseRemoteConfigException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
    if (e.throttledUntil != null) {
      print('Throttled until ${e.throttledUntil}');
    }
  } finally {
    await closeAll(remoteConfig);
  }
}
