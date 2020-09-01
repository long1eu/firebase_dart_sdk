// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:firebase_auth_vm/firebase_auth_vm.dart';
import 'package:firebase_auth_vm_example/generated/firebase_options_vm.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:firebase_core_vm/platform_dependencies.dart';
import 'package:firebase_platform_dependencies/firebase_platform_dependencies.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in_dartio/google_sign_in_dartio.dart';

import 'register_page.dart';
import 'signin_page.dart';

Future<void> main() async {
  final PlatformDependencies dependencies = await FlutterPlatformDependencies.initializeForApp();
  FirebaseApp.withOptions(firebaseOptions, dependencies: dependencies);
  if (!kIsWeb) {
    await GoogleSignInDart.register(
      clientId: firebaseOptions.clientId,
      exchangeEndpoint: 'https://us-central1-flutter-sdk.cloudfunctions.net/authHandler',
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
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Auth Demo',
      routes: <String, WidgetBuilder>{
        RegisterPage.title: (_) => const RegisterPage(),
        SignInPage.title: (_) => const SignInPage(),
      },
      home: const HomePage(
        title: 'Firebase Auth Demo',
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  FirebaseUser user;

  void _pushPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

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
              onPressed: () => _pushPage(context, const RegisterPage()),
              child: const Text('Test registration'),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: RaisedButton(
              onPressed: () => _pushPage(context, const SignInPage()),
              child: const Text('Test SignIn/SignOut'),
            ),
          ),
        ],
      ),
    );
  }
}
