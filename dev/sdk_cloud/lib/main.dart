import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const FirebaseFlutterSdk());

class FirebaseFlutterSdk extends StatelessWidget {
  const FirebaseFlutterSdk({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Flutter SDK',
      theme: ThemeData(
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Firebase Flutter SDK'),
        ),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(24.0),
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              children: <Widget>[
                const Text(
                  'All demo apps that provide authentication features uses the information received only locally. The apps are created so that you can see how to implement various APIs and how they work.',
                ),
                const SizedBox(height: 24.0),
                Text.rich(
                  TextSpan(
                    text: 'Click here for Privacy policy',
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launch('https://flutter-sdk.firebaseapp.com/pp.html');
                      },
                  ),
                ),
                const SizedBox(height: 24.0),
                Text.rich(
                  TextSpan(
                    text: 'Click here for Terms and conditions',
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launch('https://flutter-sdk.firebaseapp.com/tac.html');
                      },
                  ),
                ),
                const SizedBox(height: 24.0),
                Text.rich(
                  TextSpan(
                    text: 'Source code',
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launch(
                            'https://github.com/fluttercommunity/firebase_dart_sdk');
                      },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
