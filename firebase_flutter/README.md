# Flutter wrapper for Firebase Dart SDK

A Flutter wrapper over the Firebase Dart SDK to use the [Firebase APIs](https://firebase.google.com/docs/).

*Note*: This library is still under development, and some APIs might not be available yet or work correctly. 
Please feel free to open an issue [here](https://github.com/fluttercommunity/firebase_flutter_sdk/issues) or even a
[pull requests](https://github.com/fluttercommunity/firebase_flutter_sdk/pulls) if you feel brave.

**Currently it only supports Cloud Firestore.**

## Setup

To use this plugin:

1. Using the [Firebase Console](http://console.firebase.google.com/), add an Android app to your project:
Follow the assistant, download the generated google-services.json file and place it inside android/app. Next,
modify the android/build.gradle file and the android/app/build.gradle file to add the Google services plugin
as described by the Firebase assistant. Ensure that your `android/build.gradle` file contains the
`maven.google.com` as [described here](https://firebase.google.com/docs/android/setup#add_the_sdk).
1. Using the [Firebase Console](http://console.firebase.google.com/), add an iOS app to your project:
Follow the assistant, download the generated GoogleService-Info.plist file, open ios/Runner.xcworkspace
with Xcode, and within Xcode place the file inside ios/Runner. Don't follow the steps named
"Add Firebase SDK" and "Add initialization code" in the Firebase assistant.
1. Add `firebase_flutter` as a [dependency in your pubspec.yaml file](https://flutter.io/platform-plugins/).

## Usage

```dart
import 'package:firebase_flutter/firebase_flutter.dart';
```

To initialize the FirebaseApp change the `runApp` method with `runFirebaseApp`:

```dart
void main() {
  runFirebaseApp(app: const MaterialApp());
}
```

This automatically initialises the default FirebaseApp and the default Firestore instance. You can also provide your own
 `FirebaseOptions`:

```dart
void main() {
  runFirebaseApp(
    app: const MaterialApp(),
    options: FirebaseOptions(
      applicationId: '1:79601577497:ios:5f2bcc6ba8cecddd',
      gcmSenderId: '79601577497',
      apiKey: 'AIzaSyArgmRGfB5kiQT6CunAOmKRVKEsxKmy6YI-G72PVU',
      projectId: 'flutter-firestore',
    ),
  );
}
```

## Getting Started

See the `example` directory for a complete sample app using Cloud Firestore.