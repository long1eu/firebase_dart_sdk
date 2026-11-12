# firebase_app_dart

An unofficial, pure-Dart `FirebaseApp` / `FirebaseOptions` layer for Dart servers, CLIs and
Flutter apps. It is the app layer used by
[`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart). It is not affiliated
with or endorsed by Google or Firebase.

Renamed: this package was published as
[`firebase_core_vm`](https://pub.dev/packages/firebase_core_vm). Replace the dependency with
`firebase_app_dart` and the import with `package:firebase_app_dart/firebase_app_dart.dart`;
class names did not change.

*Status*: part of the unofficial Firestore revival (see the
[repository README](https://github.com/long1eu/firebase_dart_sdk)). It builds on Dart 3 with
null safety and its unit tests pass; it is exercised by `cloud_firestore_dart`'s integration
suite, which runs against the local Firestore emulator only. Some APIs described below date
from the original project and have not been re-verified. Issues and pull requests:
https://github.com/long1eu/firebase_dart_sdk

`package:firebase_app_dart/internal.dart` is shared plumbing for `cloud_firestore_dart`. It is
**not public API** and can change in any release.

## Platforms

Android, iOS, Linux, macOS and Windows (Dart VM, including Flutter apps). Web is not supported
yet: `FirebaseApp.withOptions` throws `UnimplementedError` in a browser, and
`cloud_firestore_dart` needs a native gRPC transport. Web support is planned.

## Usage

### 1. Add the dependency

```shell
dart pub add firebase_app_dart
```

### 2. Import it
```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
```

### 3. Create a Firebase project
If you already have a Firebase project for you mobile/web apps you can skip this step.

### 4. Initialize the FirebaseApp
```dart
import 'dart:io';

FirebaseOptions options;
if (Platform.isLinux) {
  options = const FirebaseOptions(
    apiKey: '<YOUR_API_KEY>',
    applicationId:
        '<YOUR_APP_ID>',
  );
} else if (Platform.isMacOS) {
  options = const FirebaseOptions(
    apiKey: '<YOUR_API_KEY>',
    applicationId:
        '<YOUR_APP_ID>',
  );
} else if (Platform.isWindows) {
  options = const FirebaseOptions(
    apiKey: '<YOUR_API_KEY>',
    applicationId:
        '<YOUR_APP_ID>',
  );
} else if (Platform.isAndroid) {
  options = const FirebaseOptions(
    apiKey: '<YOUR_API_KEY>',
    applicationId: '<YOUR_APP_ID>',
  );
} else if (Platform.isIOS) {
  options = const FirebaseOptions(
    apiKey: '<YOUR_API_KEY>',
    applicationId: '<YOUR_APP_ID>',
  );
} else if (Platform.isFuchsia) {
  options = const FirebaseOptions(
    apiKey: '<YOUR_API_KEY>',
    applicationId:
        '<YOUR_APP_ID>',
  );
} else {
  throw UnsupportedError('No Firebase options for this platform.');
}

FirebaseApp.withOptions(options);
```

This initializes the default `FirebaseApp` which can be accessed using `FirebaseApp.instance`. For platforms that 
Firebase does not support by default like `Windows`, `Linux`, `macOS` and others, you need to generate a unique 
`applicationId` and an `apiKey`.

#### Create API Key
1. Go to the Google Cloud Platform console and select you [project](https://console.cloud.google.com/projectselector2/home/dashboard)
1. Go to `APIs & Service` -> `Credentials`
1. Create new credentials for your app by selecting `CREATE CREDENTIALS` and then `API Key`

#### Create an Application ID
Since desktop is not an officially supported platform, we need to create `applicationId` for our local use.
1. Construct the first part of you `applicationId` following this pattern `<appCount>:<projectNumber>:<os>`.
    - `appCount` - TL;DR set it to 1. The `appNumber` is an incrementing value that starts at 1 and represents the 
    index of your applications for this platform that uses the same Firebase project.
    - `projectNumber` - is your project number and can be found on the `Google Cloud Platform Dashboard` in the 
    `Project info` card.
    - `os` - `windows`, `macos`, `linux`, `my-custom-os-because-i-can`
1. Generate the SHA1 hash of this part. You can use this [tool](https://www.sha1-online.com/)
1. Add the SHA1 hash to the first part, so you `applicationId` looks like this `<appNumber>:<gcmSenderID>:<os>:sha1(<appNumber>:<gcmSenderID>:<os>)`
(eg. `<YOUR_APP_ID>`)    
 
#### Get configuration from [Firebase console](https://console.firebase.google.com/u/0/)
1. `projectID` you can be found on the `Project Settings` tab
1. `gcmSenderID/projectNumber` you can be found on the `Project Settings` -> `Cloud Messaging` -> `Sender ID`
1. `databaseURL` you can find it on the `Database` tab and it usually looks like this `https://<project-id>.firebaseio.com`
1. `storageBucket` you can find it on the `Storage` tab and it usually looks like this `<project-id>.appspot.com`         
  

## Advanced 
### Platform dependencies

In order to provide core functionality, Firebase services requires access to different events and services. For example
Firebase Auth needs a permanent storage in witch to save the current session, tokens and other information. This helps 
by not having the user to login every time the app starts. Also Firebase Auth doesn't need to trigger a token refresh if
the app is in background. All this events and services are provided to the FirebaseApp by extending the 
`PlatformDependencies` class.        

The `PlatformDependencies` class defines the following interface:

1. `onBackgroundChanged` is a `BehaviorSubject` that should emit true when the app goes in background. Default 
implementations assumes the app never goes in background.

1. `onNetworkConnected` is a `BehaviorSubject` that should emit true when the app have internet connection. Default
implementation assumes there is always internet connection.

1. `headersBuilder` provides you a way to add headers to firebase services request. This is currently only used by 
`Firebase Auth`. Defaults to null.

1. `storage` is a simple interface that should allow to persisting key/value pairs. It's your responsibility to make sure 
the store is safe and survives app restarts. Default implementation uses an in memory storage that does not survives 
app restarts.

1. `authProvider` is used to generate authorization headers. If you plan to use `Firebase Auth`, the `authProvider` 
functionality will be provided by the corresponding `FirebaseAuth` instance. If `Firebase Auth` is not used it defaults 
to null.

All Firebase services can work with the default implementation. However it is a good idea to provide your own based on 
the application that you are trying to use. A minimal program is in `example/main.dart`.  