// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

part of 'firebase.dart';

ProjectsAndroidAppsResourceApi get androidApps =>
    _firebaseApi.projects.androidApps;

Future<void> createAndroidApp({
  @required String path,
  @required String googleServiceVersion,
  @required String name,
  @required String package,
  @required String sha1,
  @required String sha256,
}) async {
  assert(name != null && name.isNotEmpty);
  assert(package != null && package.isNotEmpty);
  assert(sha1 != null && sha1.isNotEmpty);
  assert(sha256 != null && sha256.isNotEmpty);

  final AndroidAppConfig config = await _addAndroidAppToFirebase(
    name: name,
    package: package,
    sha1: sha1,
    sha256: sha256,
  );

  final Directory androidDir = Directory('$path/example/android/');
  final Directory appDir = Directory('$path/example/android/app');

  File('${appDir.path}/${config.configFilename}')
      .writeAsBytesSync(config.configFileContentsAsBytes);

  _addGoogleServicesClasspath(androidDir, googleServiceVersion);
  _addGoogleServicesPlugin(appDir);
}

Future<AndroidAppConfig> _addAndroidAppToFirebase({
  @required String name,
  @required String package,
  @required String sha1,
  @required String sha256,
}) async {
  final AndroidApp app = await _runOperation(
    () => androidApps.create(
      AndroidApp()
        ..displayName = name
        ..packageName = package,
      _parentProject,
    ),
    (Map<String, dynamic> data) => AndroidApp.fromJson(data),
  );

  // create certificates
  final ShaCertificate sha256Cert = ShaCertificate()
    ..certType = 'SHA_256'
    ..shaHash = sha256;
  final ShaCertificate sha1Cert = ShaCertificate()
    ..certType = 'SHA_1'
    ..shaHash = sha1;

  await androidApps.sha.create(sha256Cert, app.name);
  await androidApps.sha.create(sha1Cert, app.name);

  return androidApps.getConfig('${app.name}/config');
}

void _addGoogleServicesClasspath(
    Directory androidDir, String googleServiceVersion) {
  final File rootGradleFile = File('${androidDir.path}/build.gradle');
  final String data = rootGradleFile.readAsStringSync();
  final String result = data.replaceFirstMapped(
    RegExp('classpath \'com\.android\.tools\.build(.+?)\n'),
    (Match match) =>
        '${match.group(0)}        classpath \'com.google.gms:google-services:$googleServiceVersion\'\n',
  );

  rootGradleFile.writeAsStringSync(result);
}

void _addGoogleServicesPlugin(Directory appDir) {
  final File gradleFile = File('${appDir.path}/build.gradle');
  final String data = gradleFile.readAsStringSync();
  final String result = data.replaceFirstMapped(
      RegExp('\nandroid \{\n'),
      (Match match) =>
          'apply plugin: \'com.google.gms.google-services\'\n${match.group(0)}');

  gradleFile.writeAsStringSync(result);
}
