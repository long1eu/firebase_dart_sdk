/*
// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_common/src/firebase_app.dart';
import 'package:firebase_common/src/flutter/lifecycle_handler.dart';
import 'package:firebase_common/src/util/log.dart';
import 'package:firebase_common/src/util/prefs.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

class FirebaseWidget extends StatefulWidget {
  const FirebaseWidget({Key key, this.initializeApis, this.builder})
      : super(key: key);
  final InitializeApis initializeApis;
  final WidgetBuilder builder;

  FirebaseApp of(BuildContext context) {
    return (context.inheritFromWidgetOfExactType(_FirebaseAppData)
            as _FirebaseAppData)
        ?.firebaseApp;
  }

  @override
  _FirebaseWidgetState createState() => _FirebaseWidgetState();
}

class _FirebaseWidgetState extends State<FirebaseWidget> {
  FirebaseApp firebaseApp;

  @override
  void initState() {
    super.initState();

    getApplicationDocumentsDirectory().then(
      (Directory dir) async {
        final Prefs prefs =
            Prefs(File('${dir.path}/${FirebaseApp.firebaseAppPrefs}'));

        String data;
        try {
          data = await rootBundle.loadString('google-services.json');
        } catch (e) {
          Log.d(
              'FirebaseWidget',
              'Default FirebaseApp failed to initialize because no default
              options were found. This usually means that you don\'t have the '
              'google-services.json into you assets folder or you didn\'t add'
              'it to your pubspec.yaml file.');
        }

        setState(() => firebaseApp = FirebaseApp(jsonDecode(data),
            widget.initializeApis, prefs, LifecycleHandlerImpl()));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return firebaseApp != null ? widget.builder(context) : Container();
  }
}

class _FirebaseAppData extends InheritedWidget {
  final FirebaseApp firebaseApp;

  _FirebaseAppData({Key key, this.firebaseApp, Widget child})
      : super(key: key, child: child);

  @override
  bool updateShouldNotify(_FirebaseAppData oldWidget) =>
      oldWidget.firebaseApp != firebaseApp;
}

class LifecycleHandlerImpl implements LifecycleHandler {
  static LifecycleHandlerImpl _instance = LifecycleHandlerImpl._();

  bool isBackground = true;

  LifecycleHandlerImpl._() {
    SystemChannels.lifecycle.setMessageHandler(_handler);
  }

  factory LifecycleHandlerImpl() => _instance;

  Future<String> _handler(String message) {
    final bool background = message == 'paused' || message == 'suspending';
    isBackground = background;

    for (FirebaseApp app in FirebaseApp.instances.values) {
      if (app.automaticResourceManagementEnabled) {
        app.notifyBackgroundStateChangeObservers(background);
      }
    }

    return null;
  }
}
*/
