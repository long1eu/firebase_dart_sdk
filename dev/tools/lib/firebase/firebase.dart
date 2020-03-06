// File created by
// Lung Razvan <long1eu>
// on 06/03/2020
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis_beta/firebase/v1beta1.dart';
import 'package:meta/meta.dart';
import 'package:strings/strings.dart';
import 'package:tools/run_command.dart';
import 'package:html/parser.dart';
import 'package:html/dom.dart';
part 'android.dart';

part 'ios.dart';

part 'web.dart';

AutoRefreshingAuthClient _client;
FirebaseProject _firebaseProject;

Future<void> initializeFirebase(String file) async {
  final String serviceAccount = File(file).readAsStringSync();
  _client = await clientViaServiceAccount(
    ServiceAccountCredentials.fromJson(serviceAccount),
    <String>[
      FirebaseApi.CloudPlatformScope,
      FirebaseApi.FirebaseScope,
    ],
  );

  _firebaseProject = (await _firebaseApi.projects.list()).results[0];
}

FirebaseProject get firebaseProject => _firebaseProject;

Future<void> addAppToFirebase({
  @required String path,
  @required String displayName,
  @required String org,
  @required String sha1,
  @required String sha256,
}) async {
  final String exampleAppModule = '$displayName\_example';
  final String androidPackage = '$org.$exampleAppModule';
  final String iosPackage = '$org.${camelize(exampleAppModule, true)}';

  /*await createAndroidApp(
    path: path,
    name: displayName,
    package: androidPackage,
    sha1: sha1,
    sha256: sha256,
    googleServiceVersion: '4.3.3',
  );*/
  // await createIosApp(path: path, name: displayName, bundleId: iosPackage);
  await createWebApp(displayName: displayName);
}

FirebaseApi get _firebaseApi => FirebaseApi(_client);

String get _parentProject => _firebaseProject.name;

Future<R> _runOperation<R>(Future<Operation> Function() result,
    R Function(Map<String, dynamic>) builder) async {
  final Operation operation = await result();
  final String name = operation.name;

  while (true) {
    final Operation status = await _firebaseApi.operations.get(name);
    if (status.done ?? false) {
      return builder(status.response);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}
