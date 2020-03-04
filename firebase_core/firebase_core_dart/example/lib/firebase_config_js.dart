// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_dart/firebase_core_dart.dart';

FirebaseOptions get firebaseOptions {
  assert(isWeb);
  return const FirebaseOptions(
    apiKey: 'AIzaSyDsSL36xeTPP-JdGZBdadhEm2bxNpMqlUQ',
    databaseURL: 'https://flutter-sdk.firebaseio.com',
    projectID: 'flutter-sdk',
    storageBucket: 'flutter-sdk.appspot.com',
    gcmSenderID: '233259864964',
    clientID:
        '233259864964-go57eg1ones74e03adlqvbtg2av6tivb.apps.googleusercontent.com',
    googleAppID: '1:233259864964:web:149047b5481b5479d583d1',
    trackingID: 'G-KFTS2799LM',
  );
}
