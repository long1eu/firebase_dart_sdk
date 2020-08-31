// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

import 'dart:io';

import 'package:googleapis_beta/firebase/v1beta1.dart';
import 'package:path/path.dart';
import 'package:firebase_sdk_tools/firebase/firebase.dart';

Future<void> main(List<String> args) async {
  await initializeFirebase('/Users/long1eu/IdeaProjects/firebase_flutter_sdk/dev/tools/service-account.json');

  final List<File> android = Directory.current
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File element) => !element.path.contains('/build/'))
      .where((File element) => 'google-services.json' == basename(element.path))
      .toList();

  final List<File> ios = Directory.current
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File element) => !element.path.contains('/build/'))
      .where((File element) => element.path.endsWith('/ios/Runner.xcodeproj/project.pbxproj'))
      .toList();

  await _downloadAndroid(android);
  await _downloadIos(ios);
}

Future<void> _downloadAndroid(List<File> android) async {
  final ListAndroidAppsResponse response = await firebaseApi.projects.androidApps.list(firebaseProject.name);
  final AndroidAppConfig data = await firebaseApi.projects.androidApps.getConfig('${response.apps[0].name}/config');

  for (File file in android) {
    print(file.path);
    file.writeAsBytesSync(data.configFileContentsAsBytes);
  }
}

Future<void> _downloadIos(List<File> ios) async {
  final ListIosAppsResponse iosAppsResponse = await firebaseApi.projects.iosApps.list(firebaseProject.name);
  final List<IosApp> apps = iosAppsResponse.apps;
  for (File file in ios) {
    final RegExpMatch match = RegExp('PRODUCT_BUNDLE_IDENTIFIER = (.+?);').firstMatch(file.readAsStringSync());
    final String bundleId = match.group(1);

    final IosApp app = apps.firstWhere((IosApp element) => element.bundleId == bundleId, orElse: () => null);

    final IosAppConfig config = await firebaseApi.projects.iosApps.getConfig('${app.name}/config');

    final File firebaseConfig = File('${file.parent.parent.path}/Runner/GoogleService-Info.plist');
    print(firebaseConfig.path);
    firebaseConfig.writeAsBytesSync(config.configFileContentsAsBytes);
  }
}
