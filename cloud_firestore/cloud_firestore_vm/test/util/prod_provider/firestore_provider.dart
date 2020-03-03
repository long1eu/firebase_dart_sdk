// File created by
// Lung Razvan <long1eu>
// on 08/10/2018

import 'dart:convert';
import 'dart:io';

import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// Provides locations of production Firestore and Firebase Rules.
class FirestoreProvider {
  String get firestoreHost => 'firestore.googleapis.com';

  String get projectId {
    final File config = File('${Directory.current.path}/res/google-services.json');

    hardAssert(config.existsSync(),
        'Add the \'google-services.json\' file at this path \'${Directory.current
            .path}/res/google-services.json\'');

    final Map<String, dynamic> json = jsonDecode(config.readAsStringSync());
    return json['project_info']['project_id'];
  }
}
