// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:firebase_auth_vm/firebase_auth_vm.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in_dartio/google_sign_in_dartio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './register_page.dart';
import 'firebase_config.dart';
import 'platform_dependencies.dart';
import 'signin_page.dart';

Future<void> main() async {
  if (kIsDesktop) {
    await GoogleSignInDart.register(
      exchangeEndpoint:
          'https://us-central1-flutter-sdk.cloudfunctions.net/authHandler',
      clientId:
          '233259864964-go57eg1ones74e03adlqvbtg2av6tivb.apps.googleusercontent.com',
    );
  }

  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _initFirebase();
  }

  Future<void> _initFirebase() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    FirebaseApp.withOptions(firebaseOptions,
        dependencies: Dependencies(preferences));
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Firebase Auth Demo',
      home: MyHomePage(title: 'Firebase Auth Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FirebaseUser user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: RaisedButton(
              onPressed: () => _pushPage(context, RegisterPage()),
              child: const Text('Test registration'),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: RaisedButton(
              onPressed: () => _pushPage(context, SignInPage()),
              child: const Text('Test SignIn/SignOut'),
            ),
          ),
        ],
      ),
    );
  }

  void _pushPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}
