// File created by
// Lung Razvan <long1eu>
// on 22/02/2020

import 'dart:io';

import 'package:googleapis/identitytoolkit/v3.dart';
import 'package:googleapis_auth/auth_io.dart';

Future<void> main() async {
  final ServiceAccountCredentials clientCredentials =
      ServiceAccountCredentials.fromJson(File('./configs/flutter-sdk-6fea82780c7b.json').readAsStringSync());
  final AutoRefreshingAuthClient client = await clientViaServiceAccount(
    clientCredentials,
    <String>[
      IdentitytoolkitApi.CloudPlatformScope,
      IdentitytoolkitApi.FirebaseScope,
    ],
  );

  final RelyingpartyResourceApi requester = IdentitytoolkitApi(client).relyingparty;

  print((await requester.getProjectConfig()).toJson());
}
