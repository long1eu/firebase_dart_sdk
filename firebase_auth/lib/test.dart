// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_internal/firebase_internal.dart';
import 'package:hive/hive.dart';
import 'package:meta/meta.dart';

Future<void> main() async {
  Hive.init('./hives');

  final Box<dynamic> box =
      await Hive.openBox<dynamic>('firebase_auth', encryptionKey: 'dEtk7JiOCJirguAJEM7wOSkcNtfZO0DG'.codeUnits);

  print(box.values);

  final Dependencies dependencies = Dependencies(box: box);
  final FirebaseOptions options = FirebaseOptions(
      apiKey: 'AIzaSyATj6OD0ja_nA2kaDxAlD3glZDTJiOQKL0', applicationId: '1:233259864964:ios:2577b6e25824fac5d583d1');
  FirebaseApp.withOptions(options, dependencies);

  FirebaseAuth.instance.onAuthStateChanged.listen(print);

  final FirebaseUser user = FirebaseAuth.instance.currentUser;

  FirebaseAuth.instance;

  print(user.refreshToken);
  print(await FirebaseAuth.instance.getAccessToken());


  final String verificationId = await FirebaseAuth.instance.verifyPhoneNumber(phoneNumber: '+40755769229');

  final String code = stdin.readLineSync();
  final AuthCredential credential =
      PhoneAuthProvider.getCredential(verificationId: verificationId, verificationCode: code);
  print(credential);

  await FirebaseAuth.instance.signInWithCredential(credential);

  await user.linkWithCredential(EmailAuthProvider.getCredential(email: 'lung.razvan@gmail.com', password: '123456'));
}

class Dependencies extends PlatformDependencies {
  Dependencies({@required this.box}) : headersBuilder = null;

  @override
  final Box<dynamic> box;

  @override
  final HeaderBuilder headersBuilder;

  @override
  InternalTokenProvider get authProvider => null;

  @override
  AuthUrlPresenter get authUrlPresenter => null;

  @override
  bool get isBackground => false;

  @override
  Future<bool> get isNetworkConnected => Future<bool>.value(true);

  @override
  String get locale => 'en';

  @override
  Stream<bool> get isBackgroundChanged => Stream<bool>.fromIterable(<bool>[false]);
}
