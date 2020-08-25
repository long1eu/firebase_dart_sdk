# Firebase Firestore for Dart

A Dart port of the Firebase Firestore SDK to use the [Cloud Firestore API](https://firebase.google.com/docs/firestore/).

*Note*: This library is still under development, and some APIs might not be available yet or work correctly. 
Please feel free to open an issue [here](https://github.com/fluttercommunity/firebase_flutter_sdk/issues) or even a
[pull requests](https://github.com/fluttercommunity/firebase_flutter_sdk/pulls) if you feel brave.

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
1. Add `firebase_firestore` as a [dependency in your pubspec.yaml file](https://flutter.io/platform-plugins/).

## Usage

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
```

Adding a new `DocumentReference`:

```dart
FirebaseFirestore.instance
    .collection('books')
    .document()
    .set({'title': 'title', 'author': 'author'});
```

Performing a query:
```dart
FirebaseFirestore.instance
    .collection('talks')
    .whereEqualTo('topic', 'flutter')
    .snapshots
    .listen((data) => data.documents.forEach((doc) => print(doc['title'])));
```

Running a transaction:

```dart
final DocumentReference postRef = FirebaseFirestore.instance.document('posts/123');
FirebaseFirestore.instance.runTransaction((Transaction tx) async {
  final DocumentSnapshot postSnapshot = await tx.get(postRef);
  if (postSnapshot.exists) {
    tx.update(postRef, <String, dynamic>{
      'likesCount': postSnapshot.getInt('likesCount') + 1
    });
  }
});
```