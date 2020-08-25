// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

part of 'firebase.dart';

ProjectsIosAppsResourceApi get iosApps => firebaseApi.projects.iosApps;

Future<void> createIosApp({
  @required String path,
  @required String name,
  @required String bundleId,
}) async {
  assert(name != null && name.isNotEmpty);
  assert(bundleId != null && bundleId.isNotEmpty);

  final IosAppConfig config = await _addIosAppToFirebase(name, bundleId);

  final Directory iosDir = Directory('$path/example/ios');
  final Directory runnerDir = Directory('$path/example/ios/Runner');

  File('${runnerDir.path}/${config.configFilename}')
      .writeAsBytesSync(config.configFileContentsAsBytes);

  await runCommand(
    'node',
    <String>[
      '${Directory.current.path}/dev/tools/node/lib/index.js',
      './Runner.xcodeproj/project.pbxproj',
      config.configFilename,
    ],
    workingDirectory: iosDir.path,
  );
}

Future<IosAppConfig> _addIosAppToFirebase(String name, String bundleId) async {
  final IosApp app = await _runOperation(
    () => iosApps.create(
      IosApp()
        ..displayName = name
        ..bundleId = bundleId,
      _parentProject,
    ),
    (Map<String, dynamic> data) => IosApp.fromJson(data),
  );

  return iosApps.getConfig('${app.name}/config');
}
