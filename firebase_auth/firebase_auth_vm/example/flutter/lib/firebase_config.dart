// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

import 'dart:io';

import 'package:firebase_core_vm/firebase_core_vm.dart';

FirebaseOptions get firebaseOptions {
  if (Platform.isAndroid) {
    return FirebaseOptions(
      apiKey: 'AIzaSyAM1bGAY-Bd4onFPFb2dBCJA3kx0eiWnSg',
      projectId: 'flutter-sdk',
      gcmSenderId: '233259864964',
      databaseUrl: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      applicationId: '1:233259864964:android:824fdc4c5df0d579d583d1',
    );
  } else if (Platform.isIOS) {
    return FirebaseOptions(
      apiKey: 'AIzaSyBguTk4w2Xk2LD0mSdB2Pi9LTtt5BeAE6U',
      projectId: 'flutter-sdk',
      gcmSenderId: '233259864964',
      databaseUrl: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      applicationId: '1:233259864964:ios:2523e686810855f4d583d1',
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
