// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

import 'firebase/firebase.dart';
import 'firebase/flutter.dart';

// ignore_for_file: prefer_const_declarations
Future<void> main(List<String> args) async {
  assert(args[0] != null && args[0].isNotEmpty);
  await initializeFirebase(args[0]);
  final String projectId = firebaseProject.projectId;

  /*
  name ??= 'Display Name  dfsdfs';
  package ??= 'eu.long.test';

  // eu.long1.testModuleExample
  // eu.long1.test_module_example
  */
  final String description = 'some description';
  final String org = 'eu.long1';
  final String name = 'test_module';
  final String path = './$name';
  final String sha1 = '38eb99cf2426f2ea789fce2f4f19fd14ea580167';
  final String sha256 =
      '0a12de1044e0623060576916742bd8cadb80a9c9be38303cf86c932c865fcb2e';

  await createPackage(description, org, name, path);
  /*await addAppToFirebase(
    path: path,
    displayName: name,
    org: org,
    sha1: sha1,
    sha256: sha256,
  );*/
}
