# Firebase Core

Dart implementation of the Firebase Core API, which enables connecting to multiple Firebase apps.

*Note*: This library is still under development, and some APIs might not be available yet or work correctly. 
Please feel free to open an issue [here](https://github.com/fluttercommunity/firebase_flutter_sdk/issues) or even a
[pull requests](https://github.com/fluttercommunity/firebase_flutter_sdk/pulls) if you feel brave.

*NOTES*
* can be used in CLIs, servers and Flutter.
* To use this package with the official [firebase_core](https://pub.dev/packages/firebase_core) plugin on Flutter, 
  see [firebase_core_dart](https://pub.dev/packages/firebase_core_dart).
  
## Usage

### 1. Add this to your package's dependencies and run `flutter pub get`:
```yaml
dependencies:
  firebase_core_vm: ^0.0.7
```

### 2. Import it
```dart
import 'package:firebase_core_vm/firebase_core_vm.dart';
```

### 3. Create a Firebase project
If you already have a Firebase project for you mobile/web apps you can skip this step.

### 4. Initialize the FirebaseApp
 ```dart
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
1. Generate the SHA1 hash of this part. You can use this [tool](http://www.sha1-online.com/)
1. Add the SHA1 hash to the first part, so you `applicationId` looks like this `<appNumber>:<gcmSenderID>:<os>:sha1(<appNumber>:<gcmSenderID>:<os>)`
(eg. `1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1`)    
 
### 4. Initialize multiple `FirebaseApp` objects
   1. make sure you first register this package:
      ```dart
      import 'package:firebase_core/firebase_core.dart';
      import 'package:firebase_core_dart/firebase_core_dart.dart';
      import 'package:flutter/material.dart';
      
      void main() {
        if (isDesktop) {
          FirebaseCoreDart.register();
        }
        runApp(MyApp());
      }
      ```                                      
   1. Use `firebase_core` to initialize the app you want as you normally would.
      ```dart
        Future<void> _configure() async {
          final FirebaseApp app = await FirebaseApp.configure(
            name: 'foo',
            options: const FirebaseOptions(
              apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
              databaseURL: 'https://flutter-sdk.firebaseio.com',
              projectID: 'flutter-sdk',
              storageBucket: 'flutter-sdk.appspot.com',
              gcmSenderID: '233259864964',
              clientID:
                  '233259864964-go57eg1ones74e03adlqvbtg2av6tivb.apps.googleusercontent.com',
              googleAppID:
                  '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
            ),
          );
          assert(app != null);
          print('Configured $app');
        }
      ```
      
   Note: You can have a look at the example app on how you can initialize use different `FirebaseOptions` 
   depending on the platform you are on.       
   
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
the application that you are trying to use. You can find a good example [here](https://github.com/fluttercommunity/firebase_dart_sdk/blob/develop/firebase_auth/firebase_auth_vm/example/flutter/lib/platform_dependencies.dart).  