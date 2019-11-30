// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_internal/firebase_internal.dart';
import 'package:hive/hive.dart';
import 'package:meta/meta.dart';

Future<void> main() async {
  Hive.init('./hives');

  final Box<dynamic> box =
      await Hive.openBox<dynamic>('firebase_auth', encryptionKey: 'dEtk7JiOCJirguAJEM7wOSkcNtfZO0DG'.codeUnits);

  final Dependencies dependencies = Dependencies(box: box);
  final FirebaseOptions options = FirebaseOptions(
      apiKey: 'AIzaSyApD5DJ2oSzosgy-pT0HPfqtCNh7st9dwM', applicationId: '1:233259864964:android:ef48439a0cc0263d');
  FirebaseApp.withOptions(options, dependencies);

  const String email = 'lungrazvan@gmail.cl';
  const String password = '123456';

  FirebaseAuth.instance.onAuthStateChanged.listen(print);

  if (FirebaseAuth.instance.currentUser != null) {
    await FirebaseAuth.instance.getAccessToken();
    print(FirebaseAuth.instance.currentUser.refreshToken);
  }

  await Future<void>.delayed(Duration(seconds: 1));

  // print(FirebaseAuth.instance.currentUser);
  // print(await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password));
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
  Stream<bool> get isBackgroundChanged => Stream<bool>.fromIterable(<bool>[true]);
}
