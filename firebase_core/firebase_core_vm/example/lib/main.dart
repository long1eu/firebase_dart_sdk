// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_dependencies.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  final String name = 'foo';
  final FirebaseOptions options = FirebaseOptions(
    applicationId: '1:297855924061:ios:c6de2b69b03a5be8',
    gcmSenderId: '297855924061',
    apiKey: 'AIzaSyBq6mcufFXfyqr79uELCiqM_O_1-G72PVU',
  );

  Future<void> _configure() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final PlatformDependencies platform = PlatformDependencies(preferences);

    final FirebaseApp app =
        FirebaseApp.withOptions(options, name: name, dependencies: platform);
    assert(app != null);
    print('Configured $app');
  }

  Future<void> _allApps() async {
    final List<FirebaseApp> apps = FirebaseApp.apps;
    print('Currently configured apps: $apps');
  }

  Future<void> _options() async {
    try {
      final FirebaseApp app = FirebaseApp.getInstance(name);
      final FirebaseOptions options = app.options;
      print('Current options for app $name: $options');
    } catch (e) {
      print('The app has not been yet initialized.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Firebase Core example app'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              RaisedButton(
                onPressed: _configure,
                child: const Text('initialize'),
              ),
              RaisedButton(
                onPressed: _allApps,
                child: const Text('allApps'),
              ),
              RaisedButton(
                onPressed: _options,
                child: const Text('options'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
