// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_dart/firebase_core_dart.dart';

FirebaseOptions get firebaseOptions {
  if (isDesktop) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
      databaseURL: 'https://flutter-sdk.firebaseio.com',
      projectID: 'flutter-sdk',
      storageBucket: 'flutter-sdk.appspot.com',
      gcmSenderID: '233259864964',
      googleAppID:
          '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
    );
  } else {
    assert(isMobile);
    return FirebaseOptions(
      apiKey: Platform.isIOS
          ? 'AIzaSyBguTk4w2Xk2LD0mSdB2Pi9LTtt5BeAE6U'
          : 'AIzaSyAM1bGAY-Bd4onFPFb2dBCJA3kx0eiWnSg',
      bundleID: 'eu.long1.firebaseCoreDartExample',
      androidClientID:
          '233259864964-atj096gj4dkn2q5iciufgrugequubseo.apps.googleusercontent.com',
      clientID:
          '233259864964-6agjde1utg6tml9bbe3uag4ppq8ogkb1.apps.googleusercontent.com',
      googleAppID: Platform.isIOS
          ? '1:233259864964:ios:875d94c61884160dd583d1'
          : '1:233259864964:android:87954400984e5506d583d1',
      databaseURL: 'https://flutter-sdk.firebaseio.com',
      projectID: 'flutter-sdk',
      storageBucket: 'flutter-sdk.appspot.com',
      gcmSenderID: '233259864964',
    );
  }
}
