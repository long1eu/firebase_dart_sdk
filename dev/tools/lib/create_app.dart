// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

import 'package:args/args.dart';

import 'firebase/firebase.dart';
import 'firebase/flutter.dart';

// ignore_for_file: prefer_const_declarations
Future<void> main(List<String> args) async {
  final ArgParser parser = ArgParser()
    ..addOption('serviceAccount', abbr: 'a')
    ..addOption('name', abbr: 'n')
    ..addOption('org', abbr: 'o')
    ..addOption('description', abbr: 'd')
    ..addOption('path', abbr: 'p')
    ..addOption('sha1')
    ..addOption('sha256')
    ..addOption('webClientId', abbr: 'w');

  final ArgResults result = parser.parse(args);
  if (result['serviceAccount'] == null) {
    throw const FormatException('serviceAccount');
  }
  if (result['name'] == null) {
    throw const FormatException('name');
  }
  if (result['org'] == null) {
    throw const FormatException('org');
  }
  if (result['description'] == null) {
    throw const FormatException('description');
  }
  if (result['path'] == null) {
    throw const FormatException('path');
  }
  if (result['sha1'] == null) {
    throw const FormatException('sha1');
  }
  if (result['sha256'] == null) {
    throw const FormatException('sha256');
  }
  if (result['webClientId'] == null) {
    throw const FormatException('webClientId');
  }

  final String serviceAccount = result['serviceAccount'];
  final String name = result['name'];
  final String org = result['org'];
  final String description = result['description'];
  final String path = result['path'];
  final String sha1 = result['sha1'];
  final String sha256 = result['sha256'];
  final String webClientId = result['webClientId'];

  await initializeFirebase(serviceAccount);
  await createPackage(description, org, name, path);
  await addAppToFirebase(
    path: path,
    displayName: name,
    org: org,
    sha1: sha1,
    sha256: sha256,
    webClientId: webClientId,
  );
}
