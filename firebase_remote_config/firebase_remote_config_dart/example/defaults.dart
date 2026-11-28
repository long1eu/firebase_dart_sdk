// Defaults, typed reads and the fall-through rules: a remote value that does
// not convert falls back to the default, then to false, 0 or 0.0.
//
//     dart run example/defaults.dart --api-key <key> --app-id <id> --project-id <project>

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final FirebaseRemoteConfig remoteConfig = exampleRemoteConfig(
    arguments,
    defaults: <String, Object>{
      'feature_enabled': false,
      'max_items': 20,
      'discount': 0.1,
      'banner_text': 'Welcome',
    },
  );
  try {
    // Reads work before anything is fetched, even before the stored records
    // are loaded: they answer from the defaults.
    print(
      'before: ${remoteConfig.getBool('feature_enabled')}, '
      '${remoteConfig.getInt('max_items')}, '
      '${remoteConfig.getDouble('discount')}, '
      '"${remoteConfig.getString('banner_text')}"',
    );

    await remoteConfig.fetchAndActivate();

    print(
      'after: ${remoteConfig.getBool('feature_enabled')}, '
      '${remoteConfig.getInt('max_items')}, '
      '${remoteConfig.getDouble('discount')}, '
      '"${remoteConfig.getString('banner_text')}"',
    );

    // A key that is neither remote nor a default has a static value.
    final RemoteConfigValue missing = remoteConfig.getValue('no_such_key');
    print(
      'missing: "${missing.asString()}" (${missing.source.name}), '
      'asBool: ${missing.asBool()}',
    );
  } on FirebaseRemoteConfigException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await closeAll(remoteConfig);
  }
}
