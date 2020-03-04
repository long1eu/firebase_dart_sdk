## firebase_auth_dart
This is a pure Dart implementation for [firebase_core](https://pub.dev/packages/firebase_core) intended for use with 
Flutter. This package uses [firebase_core_vm](https://pub.dev/packages/firebase_core_vm) to provide the pure dart 
implementation which does not and will not support Web apps. While this package will work on Android and iOS, this is 
not our main focus as for for now, instead we want to bring *Firebase to Flutter Desktop*.

This package lets you use the `firebase_core` as you would normally do so you don't need to change you code. If you 
don't want to use `firebase_core` you can directly use the `firebase_core_vm`. 

### Usage
#### 1. Add this to your package's dependencies and run `flutter pub get`:
```yaml
dependencies:
  firebase_core: ^0.4.4+2
  firebase_auth_dart: ^0.0.1
```

#### 2. Import it
```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth_dart/firebase_auth_dart.dart';
```

#### 3. Create a Firebase project
If you already have a Firebase project for you mobile/web apps you can skip this step.

#### 4. Initialize the FirebaseApp
 ```dart
 import 'package:firebase_core/firebase_core.dart';
 import 'package:firebase_auth_dart/firebase_auth_dart.dart';
 import 'package:flutter/material.dart';
 
 void main() {
   if (isDesktop) {
     FirebaseAuthDart.register(
       options: const FirebaseOptions(
         apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
         projectID: 'flutter-sdk',
         gcmSenderID: '233259864964',
         databaseURL: 'https://flutter-sdk.firebaseio.com',
         storageBucket: 'flutter-sdk.appspot.com',
         clientID:
             '233259864964-go57eg1ones74e03adlqvbtg2av6tivb.apps.googleusercontent.com',
         googleAppID:
             '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
       ),
     );
   }
   runApp(MyApp());
 }
 ``` 
Note: 
* If you want to use multiple `FirebaseApp`s skip to next section on how to do that.
* `isDesktop` is false Web/Mobile context and uses [conditional import](https://github.com/fluttercommunity/firebase_dart_sdk/blob/develop/firebase_core/firebase_core_vm/lib/firebase_core_vm.dart) to achieve that  

##### Create API Key
1. Go to the Google Cloud Platform console and select you [project](https://console.cloud.google.com/projectselector2/home/dashboard)
1. Go to `APIs & Service` -> `Credentials`
1. Create new credentials for your app by selecting `CREATE CREDENTIALS` and then `API Key`

##### Create Client ID
If you plan to use Google Sign In, the you need to create a Client ID for you app
1. Go to the Google Cloud Platform console and select you [project](https://console.cloud.google.com/projectselector2/home/dashboard) 
1. Go to `APIs & Service` -> `Credentials`
1. Create new credentials for your app by selecting `CREATE CREDENTIALS` and then `OAuth client ID`
1. Select `Other` as `Application type`, give it a name (eg. macOS) and then click `Create`

##### Get configuration from [Firebase console](https://console.firebase.google.com/u/0/)
1. `projectID` you can be found on the `Project Settings` tab
1. `gcmSenderID` you can be found on the `Project Settings` -> `Cloud Messaging` -> `Sender ID`
1. `databaseURL` you can find it on the `Database` tab and it usually looks like this `https://<project-id>.firebaseio.com`
1. `storageBucket` you can find it on the `Storage` tab and it usually looks like this `<project-id>.appspot.com`

##### Create a `applicationId`
Since desktop is not an officially supported platform, we need to create `applicationId` for our local use.
1. Construct the first part of you `applicationId` following this pattern `<appNumber>:<gcmSenderID>:<os>`.
    - `googleAppId` - TL;DR set it to 1. The `appNumber` is an incrementing value that starts at 1 and represents the index of your applications for this 
     platform that uses the same Firebase project.
    - `gcmSenderID` - you can be found on the `Project Settings` -> `Cloud Messaging` -> `Sender ID`
    - `os` - `windows`, `macos`, `linux`, `my-custom-os-because-i-can`
1. Generate the SHA1 hash of this part. You can use this [tool](http://www.sha1-online.com/)
1. add this value to the first part so you `applicationId` looks like this `<appNumber>:<gcmSenderID>:<platform>:sha1(<appNumber>:<gcmSenderID>:<os>)`
(eg. `1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1`)  
 
#### 4. Initialize multiple `FirebaseApp`s           
   1. make sure you first register this package:
      ```dart
      import 'package:firebase_core/firebase_core.dart';
      import 'package:firebase_auth_dart/firebase_auth_dart.dart';
      import 'package:flutter/material.dart';
      
      void main() {
        if (isDesktop) {
          FirebaseAuthDart.register();
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