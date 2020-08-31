// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart/firebase_auth_dart.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:firebase_core_dart/firebase_core_dart.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart' show kIsDesktop;
import 'package:flutter/material.dart';
import 'package:google_sign_in_dartio/google_sign_in_dartio.dart';

import './register_page.dart';
import './signin_page.dart';

void main() {
  if (kIsDesktop) {
    Future.wait(<Future<void>>[
      GoogleSignInDart.register(
        exchangeEndpoint:
            'https://us-central1-flutter-sdk.cloudfunctions.net/authHandler',
        clientId:
            '233259864964-go57eg1ones74e03adlqvbtg2av6tivb.apps.googleusercontent.com',
      ),
      FirebaseCoreDart.register(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
          databaseURL: 'https://flutter-sdk.firebaseio.com',
          projectID: 'flutter-sdk',
          storageBucket: 'flutter-sdk.appspot.com',
          gcmSenderID: '233259864964',
          googleAppID:
              '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
        ),
      ),
      FirebaseAuthDart.register(),
    ]);
  }
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
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
