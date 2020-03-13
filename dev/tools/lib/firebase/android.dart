// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

part of 'firebase.dart';

ProjectsAndroidAppsResourceApi get androidApps =>
    firebaseApi.projects.androidApps;

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

  File('$path/example/android/upload.key').writeAsBytesSync(base64Decode(_key));
}

Future<AndroidAppConfig> _addAndroidAppToFirebase({
  @required String name,
  @required String package,
  @required String sha1,
  @required String sha256,
}) async {
  final AndroidApp app = await _runOperation(
        () =>
        androidApps.create(
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

void _addGoogleServicesClasspath(Directory androidDir,
    String googleServiceVersion) {
  final File rootGradleFile = File('${androidDir.path}/build.gradle');
  final String data = rootGradleFile.readAsStringSync();
  final String result = data.replaceFirstMapped(
    RegExp('classpath \'com\.android\.tools\.build(.+?)\n'),
        (Match match) =>
    '${match.group(
        0)}        classpath \'com.google.gms:google-services:$googleServiceVersion\'\n',
  );

  rootGradleFile.writeAsStringSync(result);
}

void _addGoogleServicesPlugin(Directory appDir) {
  final File gradleFile = File('${appDir.path}/build.gradle');
  final String data = gradleFile.readAsStringSync();
  final String result = data.replaceFirstMapped(
      RegExp('\nandroid \{\n'),
          (Match match) =>
      'apply plugin: \'com.google.gms.google-services\'\n${match.group(0)}')
  .replaceAll('    buildTypes {', '$_keyConfig\n\n    buildTypes {');


  gradleFile.writeAsStringSync(result);
}

String _key =
    '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';

String _keyConfig = '''    signingConfigs {
        debug {
            storeFile file('../upload.key')
            storePassword 'key_password'
            keyAlias = 'key0'
            keyPassword 'alias_password'
        }
    }''';