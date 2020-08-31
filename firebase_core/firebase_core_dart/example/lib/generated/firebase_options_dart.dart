// GENERATED_FILE: DO NOT EDIT

import 'dart:io';

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart' show kIsWeb;

FirebaseOptions get firebaseOptions {
  if (!kIsWeb && Platform.operatingSystem == 'android') {
    return const FirebaseOptions(
      apiKey: 'AIzaSyAM1bGAY-Bd4onFPFb2dBCJA3kx0eiWnSg',
      appId: '1:233259864964:android:b2ec71b130a3170cd583d1',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
      databaseURL: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      authDomain: 'flutter-sdk.firebaseapp.com',
    );
  } else if (!kIsWeb && Platform.operatingSystem == 'ios') {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBguTk4w2Xk2LD0mSdB2Pi9LTtt5BeAE6U',
      appId: '1:233259864964:ios:fff621fea008bff1d583d1',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
      databaseURL: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      authDomain: 'flutter-sdk.firebaseapp.com',
    );
  } else if (kIsWeb) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
      appId: '1:233259864964:web:95ef638de4a4693dd583d1',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
      databaseURL: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      authDomain: 'flutter-sdk.firebaseapp.com',
      measurementId: 'G-KFTS2799LM',
    );
  } else if (!kIsWeb && Platform.operatingSystem == 'linux') {
    return const FirebaseOptions(
      apiKey: 'AIzaSyD9HeqeXUOXJh_DPDl211x8seUXlNmiJj0',
      appId: '1:233259864964:linux:0034c73393cdd58c1d50ac24850d6d01f1e57aff',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
      databaseURL: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      authDomain: 'flutter-sdk.firebaseapp.com',
    );
  } else if (!kIsWeb && Platform.operatingSystem == 'macos') {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
      appId: '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
      databaseURL: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      authDomain: 'flutter-sdk.firebaseapp.com',
    );
  } else if (!kIsWeb && Platform.operatingSystem == 'windows') {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBNeYDWMlalWRL2M2_UhE5kiMmvVf3o9BM',
      appId: '1:233259864964:windows:637a426b03bae337782539864340b6b22a4d2f7f',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
      databaseURL: 'https://flutter-sdk.firebaseio.com',
      storageBucket: 'flutter-sdk.appspot.com',
      authDomain: 'flutter-sdk.firebaseapp.com',
    );
  } else {
    throw UnsupportedError('${Platform.operatingSystem} not supported.');
  }
}

