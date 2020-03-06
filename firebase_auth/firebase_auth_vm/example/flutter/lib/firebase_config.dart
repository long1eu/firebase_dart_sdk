// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

import 'dart:io';

import 'package:firebase_core_vm/firebase_core_vm.dart';

FirebaseOptions get firebaseOptions {
  if (Platform.isAndroid) {
    return FirebaseOptions(
      apiKey: 'AIzaSyAwQpoxEEkD3boOaDjR8BcQbTq5cPIZdM4',
      projectId: 'flutter-sdk',
      gcmSenderId: '233259864964',
      databaseUrl: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      applicationId: '1:233259864964:android:5c5f17fc0eb54306d583d1',
    );
  } else if (Platform.isIOS) {
    return FirebaseOptions(
      apiKey: 'AIzaSyAA9H5zYPCBfj0xfohHaaKsZg3QM7yNQ3s',
      projectId: 'flutter-sdk',
      gcmSenderId: '233259864964',
      databaseUrl: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      applicationId: '1:233259864964:ios:8b858d19153dd6aed583d1',
    );
  } else {
    return FirebaseOptions(
      apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
      projectId: 'flutter-sdk',
      gcmSenderId: '233259864964',
      databaseUrl: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      applicationId:
          '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
    );
  }
}
