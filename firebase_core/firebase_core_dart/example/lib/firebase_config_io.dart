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
          ? 'AIzaSyAA9H5zYPCBfj0xfohHaaKsZg3QM7yNQ3s'
          : 'AIzaSyAwQpoxEEkD3boOaDjR8BcQbTq5cPIZdM4',
      bundleID: 'eu.long1.FirebaseCoreDartExample',
      androidClientID:
          '233259864964-dd2qk2ite8qpf8vh8f3v10trocu0nojp.apps.googleusercontent.com',
      clientID:
          '233259864964-ok8fnltaunhabf0jvcbfjk2fhdp7j578.apps.googleusercontent.com',
      googleAppID: Platform.isIOS
          ? '1:233259864964:ios:8b858d19153dd6aed583d1'
          : '1:233259864964:android:5c5f17fc0eb54306d583d1',
      databaseURL: 'https://flutter-sdk.firebaseio.com',
      projectID: 'flutter-sdk',
      storageBucket: 'flutter-sdk.appspot.com',
      gcmSenderID: '233259864964',
    );
  }
}
