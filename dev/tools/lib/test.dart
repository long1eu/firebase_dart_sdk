// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

import 'package:html/dom.dart';
import 'package:html/parser.dart';

void main() {
  final Document document = HtmlParser(htmlFile).parse();

  final data = document.head.children.map((e) => e.localName).toList();

  /*
      <script src="https://www.gstatic.com/firebasejs/7.10.0/firebase-app.js"></script>
    <script src="https://www.gstatic.com/firebasejs/7.10.0/firebase-auth.js"></script>
    <script src="https://www.gstatic.com/firebasejs/7.10.0/firebase-analytics.js"></script>
  * */

  document.head
    ..append(document.createElement('script')
      ..attributes['src'] =
          'https://www.gstatic.com/firebasejs/7.10.0/firebase-app.js')
    ..append(document.createElement('script')
      ..attributes['src'] =
          'https://www.gstatic.com/firebasejs/7.10.0/firebase-auth.js')
    ..append(document.createElement('script')
      ..attributes['src'] =
          'https://www.gstatic.com/firebasejs/7.10.0/firebase-analytics.js')
    ..append(
      document.createElement('script')
        ..innerHtml = '''// Your web app's Firebase configuration
        firebase.initializeApp({
            "projectId": "flutter-sdk",
            "appId": "1:233259864964:web:bd97f4f6e4f7d0ecd583d1",
            "databaseURL": "https://flutter-sdk.firebaseio.com",
            "storageBucket": "flutter-sdk.appspot.com",
            "locationId": "us-central",
            "apiKey": "AIzaSyDsSL36xeTPP-JdGZBdadhEm2bxNpMqlUQ",
            "authDomain": "flutter-sdk.firebaseapp.com",
            "messagingSenderId": "233259864964",
            "measurementId": "G-H63SWQMHFL"
        });
        firebase.analytics();''',
    );


  print(document.outerHtml);
}

const String htmlFile = '''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta content="IE=Edge" http-equiv="X-UA-Compatible">
    <meta name="description" content="A new Flutter project.">

    <!-- iOS meta tags & icons -->
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black">
    <meta name="apple-mobile-web-app-title" content="firebase_auth_dart_example">
    <link rel="apple-touch-icon" href="/icons/Icon-192.png">

    <!-- Favicon -->
    <link rel="shortcut icon" type="image/png" href="/favicon.png"/>

    <title>firebase_auth_dart_example</title>
    <meta name="google-signin-client_id"
          content="233259864964-atj096gj4dkn2q5iciufgrugequubseo.apps.googleusercontent.com"/>
    <link rel="manifest" href="/manifest.json">
</head>
<body>
<!-- This script installs service_worker.js to provide PWA functionality to
     application. For more information, see:
     https://developers.google.com/web/fundamentals/primers/service-workers -->
<script>
    if ('serviceWorker' in navigator) {
        window.addEventListener('load', function () {
            navigator.serviceWorker.register('/flutter_service_worker.js');
        });
    }
</script>
<script src="main.dart.js" type="application/javascript"></script>
</body>
</html>
''';
