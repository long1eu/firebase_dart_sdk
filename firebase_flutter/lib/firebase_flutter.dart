// File created by
// Lung Razvan <long1eu>
// on 19/10/2018

import 'dart:async';
import 'dart:io';

import 'package:connectivity/connectivity.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/firebase_firestore.dart';
import 'package:firebase_flutter/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:user_preferences/user_preferences.dart';

Future<void> runFirebaseApp({
  @required Widget app,
  FirebaseOptions options,
  bool firestore = true,
}) async {
  final Map<String, String> googleConfig = await FirebaseFlutter.googleConfig;
  final String uid = googleConfig['uid'];

  String documentsDirectory = googleConfig['documents_directory'];
  String databaseDirectory = documentsDirectory;

  if (Platform.isAndroid) {
    documentsDirectory = Directory(documentsDirectory).parent.path;
    databaseDirectory = '$documentsDirectory/databases';
  }

  await UserPreferences.initInstance(
    'user_prefs/${FirebaseApp.firebaseAppPrefs}.json',
    Directory(documentsDirectory),
  );

  FirebaseApp firebaseApp;
  if (options != null) {
    firebaseApp = FirebaseApp.withOptions(
      options,
      _TokenProvider(uid),
      connectivity,
    );
  } else {
    firebaseApp = FirebaseApp(
      googleConfig,
      _TokenProvider(uid),
      connectivity,
    );
  }

  if (firestore) {
    await FirebaseFirestore.getInstance(
      firebaseApp,
      openDatabase: (String name,
          {int version,
          OnConfigure onConfigure,
          OnCreate onCreate,
          OnVersionChange onUpgrade,
          OnVersionChange onDowngrade,
          OnOpen onOpen}) {
        return DatabaseImplementation.create(
          '$name.db',
          '$databaseDirectory/$name.db',
          version: version,
          onConfigure: onConfigure,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: onDowngrade,
          onOpen: onOpen,
        );
      },
    );
  }

  runApp(_LifecycleHandler(app: app));
}

Future<bool> connectivity() => Connectivity()
    .checkConnectivity()
    .then((ConnectivityResult it) => it != ConnectivityResult.none);

class _LifecycleHandler extends StatefulWidget {
  const _LifecycleHandler({Key key, this.app}) : super(key: key);

  final Widget app;

  @override
  _LifecycleHandlerState createState() => _LifecycleHandlerState();
}

class _LifecycleHandlerState extends State<_LifecycleHandler>
    with WidgetsBindingObserver {
  bool isBackground = false;

  @override
  void initState() {
    super.initState();
    FirebaseApp.instance.isInBackground = () => isBackground;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    isBackground = state == AppLifecycleState.paused;
  }

  @override
  Widget build(BuildContext context) => widget.app;
}

class _TokenProvider extends InternalTokenProvider {
  _TokenProvider(this._uid);

  String _uid;

  @override
  Future<GetTokenResult> getAccessToken(bool forceRefresh) async {
    final FirebaseUser user = await FirebaseAuth.instance.currentUser();
    final IdTokenResult token = await user?.getIdToken(refresh: forceRefresh);
    return GetTokenResult(token.token);
  }

  @override
  Stream<InternalTokenResult> get onTokenChanged =>
      FirebaseAuth.instance.onAuthStateChanged.asyncMap((FirebaseUser user) {
        _uid = user.uid;
        return user?.getIdToken();
      }).map((IdTokenResult token) => InternalTokenResult(token.token));

  @override
  String get uid => _uid;
}

class FirebaseFlutter {
  static const MethodChannel _channel = MethodChannel('firebase_flutter');

  static Future<Map<String, String>> get googleConfig async {
    final Map<dynamic, dynamic> data =
        await _channel.invokeMethod('googleConfig');
    return data.cast<String, String>();
  }
}
