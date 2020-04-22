// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseOptions options;
  if (Platform.isLinux) {
    options = const FirebaseOptions(
      apiKey: 'AIzaSyD9HeqeXUOXJh_DPDl211x8seUXlNmiJj0',
      applicationId:
          '1:233259864964:linux:0034c73393cdd58c1d50ac24850d6d01f1e57aff',
    );
  } else if (Platform.isMacOS) {
    options = const FirebaseOptions(
      apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
      applicationId:
          '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
    );
  } else if (Platform.isWindows) {
    options = const FirebaseOptions(
      apiKey: 'AIzaSyBNeYDWMlalWRL2M2_UhE5kiMmvVf3o9BM',
      applicationId:
          '1:233259864964:windows:0034c73393cdd58c1d50ac24850d6d01f1e57aff',
    );
  } else if (Platform.isAndroid) {
    options = const FirebaseOptions(
      apiKey: 'AIzaSyAM1bGAY-Bd4onFPFb2dBCJA3kx0eiWnSg',
      applicationId: '1:233259864964:android:b2ec71b130a3170cd583d1',
    );
  } else if (Platform.isIOS) {
    options = const FirebaseOptions(
      apiKey: 'AIzaSyBguTk4w2Xk2LD0mSdB2Pi9LTtt5BeAE6U',
      applicationId: '1:233259864964:ios:fff621fea008bff1d583d1',
    );
  } else if (Platform.isFuchsia) {
    options = const FirebaseOptions(
      apiKey: 'AIzaSyBOPFxmw3fni8Inzb_RhFDjb9zznXHfaRo',
      applicationId:
          '1:233259864964:fuchsia:8fc440667cd119c335cf58c7cbfd4374f96fe786',
    );
  }

  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final PlatformDependencies platform = PlatformDependencies(preferences);
  FirebaseApp.withOptions(options, name: 'foo', dependencies: platform);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final String name = 'foo';

  Future<void> _configure() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final PlatformDependencies platform = PlatformDependencies(preferences);

    final FirebaseApp app =
        FirebaseApp.withOptions(options, name: name, dependencies: platform);
    assert(app != null);
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

FirebaseOptions get options {
  if (Platform.isAndroid) {
    return const FirebaseOptions(
      applicationId: '1:233259864964:android:b2ec71b130a3170cd583d1',
      apiKey: 'AIzaSyAM1bGAY-Bd4onFPFb2dBCJA3kx0eiWnSg',
    );
  } else if (Platform.isIOS) {
    return const FirebaseOptions(
      applicationId: '1:233259864964:ios:fff621fea008bff1d583d1',
      apiKey: 'AIzaSyBguTk4w2Xk2LD0mSdB2Pi9LTtt5BeAE6U',
    );
  } else {
    return const FirebaseOptions(
      applicationId:
          '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
      apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
    );
  }
}
