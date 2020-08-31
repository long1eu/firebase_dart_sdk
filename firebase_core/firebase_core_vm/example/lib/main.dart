import 'dart:async';

import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:firebase_core_vm_example/generated/firebase_options_vm.dart';
import 'package:flutter/material.dart';

import 'platform_dependencies.dart';

Future<void> main() async {
  await PlatformDependencies.initialize();

  FirebaseApp.withOptions(firebaseOptions, dependencies: PlatformDependencies.instance);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final String _name = 'foo';
  String _message = '';

  Future<void> _configure() async {
    final bool exists = FirebaseApp.apps.any((FirebaseApp app) => app.name == _name);
    if (exists) {
      final FirebaseApp app = FirebaseApp.getInstance(_name);

      setState(() {
        _message = 'App $_name already exists with ${app.options}.';
      });
    } else {
      // probably you are going to use a different set of options
      final FirebaseApp app =
          FirebaseApp.withOptions(firebaseOptions, name: _name, dependencies: PlatformDependencies.instance);

      setState(() {
        _message = 'App $_name was configured with ${app.options}';
      });
    }
  }

  Future<void> _allApps() async {
    final List<FirebaseApp> apps = FirebaseApp.apps;
    setState(() {
      _message = 'Currently configured apps: $apps';
    });
  }

  Future<void> _options() async {
    try {
      final FirebaseApp app = FirebaseApp.getInstance(_name);
      final FirebaseOptions options = app.options;
      setState(() {
        _message = 'Current options for app $_name: $options';
      });
    } catch (e) {
      setState(() {
        _message = 'The app has not been yet initialized.';
      });
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
              Expanded(
                child: SingleChildScrollView(
                  child: Text(_message),
                ),
              ),
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
