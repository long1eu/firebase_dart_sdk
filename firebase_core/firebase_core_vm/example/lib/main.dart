import 'dart:async';
import 'dart:io';

import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:flutter/material.dart';

import 'platform_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformDependencies.initialize();

  FirebaseApp.withOptions(options, dependencies: PlatformDependencies.instance);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final String _name = 'foo';
  String _message;

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
          FirebaseApp.withOptions(options, name: _name, dependencies: PlatformDependencies.instance);

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
              if (_message != null)
                Expanded(
                  child: Center(
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

FirebaseOptions get options {
  if (Platform.isLinux) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyD9HeqeXUOXJh_DPDl211x8seUXlNmiJj0',
      appId: '1:233259864964:linux:0034c73393cdd58c1d50ac24850d6d01f1e57aff',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else if (Platform.isMacOS) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
      appId: '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else if (Platform.isWindows) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBNeYDWMlalWRL2M2_UhE5kiMmvVf3o9BM',
      appId: '1:233259864964:windows:0034c73393cdd58c1d50ac24850d6d01f1e57aff',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else if (Platform.isAndroid) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyAM1bGAY-Bd4onFPFb2dBCJA3kx0eiWnSg',
      appId: '1:233259864964:android:b2ec71b130a3170cd583d1',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else if (Platform.isIOS) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBguTk4w2Xk2LD0mSdB2Pi9LTtt5BeAE6U',
      appId: '1:233259864964:ios:fff621fea008bff1d583d1',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else if (Platform.isFuchsia) {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBOPFxmw3fni8Inzb_RhFDjb9zznXHfaRo',
      appId: '1:233259864964:fuchsia:8fc440667cd119c335cf58c7cbfd4374f96fe786',
      messagingSenderId: '233259864964',
      projectId: 'flutter-sdk',
    );
  } else {
    throw UnimplementedError();
  }
}
