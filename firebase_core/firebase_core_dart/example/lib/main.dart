// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_dart/firebase_core_dart.dart';
import 'package:flutter/material.dart';

import 'firebase_config_js.dart' if (dart.library.io) 'firebase_config_io.dart';

void main() {
  if (isDesktop) {
    FirebaseCoreDart.register();
  }
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final String name = 'foo';

  Future<void> _configure() async {
    final FirebaseApp app =
        await FirebaseApp.configure(name: name, options: firebaseOptions);
    assert(app != null);
    print('Configured $app');
  }

  Future<void> _allApps() async {
    final List<FirebaseApp> apps = await FirebaseApp.allApps();
    print('Currently configured apps: $apps');
  }

  Future<void> _options() async {
    final FirebaseApp app = await FirebaseApp.appNamed(name);
    final FirebaseOptions options = await app?.options;
    print('Current options for app $name: $options');
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
                  onPressed: _configure, child: const Text('initialize')),
              RaisedButton(onPressed: _allApps, child: const Text('allApps')),
              RaisedButton(onPressed: _options, child: const Text('options')),
            ],
          ),
        ),
      ),
    );
  }
}
