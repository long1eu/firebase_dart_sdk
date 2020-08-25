// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

FirebaseOptions get firebaseOptions {
  if (Platform.isLinux) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyD9HeqeXUOXJh_DPDl211x8seUXlNmiJj0',
      appId: '1:233259864964:linux:0034c73393cdd58c1d50ac24850d6d01f1e57aff',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else if (Platform.isMacOS) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
      appId: '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else if (Platform.isWindows) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBNeYDWMlalWRL2M2_UhE5kiMmvVf3o9BM',
      appId: '1:233259864964:windows:0034c73393cdd58c1d50ac24850d6d01f1e57aff',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else if (Platform.isAndroid) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyAM1bGAY-Bd4onFPFb2dBCJA3kx0eiWnSg',
      appId: '1:233259864964:android:b2ec71b130a3170cd583d1',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else if (Platform.isIOS) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBguTk4w2Xk2LD0mSdB2Pi9LTtt5BeAE6U',
      appId: '1:233259864964:ios:fff621fea008bff1d583d1',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else if (Platform.isFuchsia) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBOPFxmw3fni8Inzb_RhFDjb9zznXHfaRo',
      appId: '1:233259864964:fuchsia:8fc440667cd119c335cf58c7cbfd4374f96fe786',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else {
    throw UnimplementedError();
  }
}
