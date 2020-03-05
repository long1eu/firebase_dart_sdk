# google_sign_in_dart

A Flutter package that implements [Google Sign In](https://developers.google.com/identity/) in pure Dart. This package 
is compatible with `google_sign_in` plugin and works on all platforms Flutter supports. 

## Getting Started

### Install and initialization
1. Depend on it
    ```yaml
    dependencies:
      google_sign_in: ^4.1.4
      google_sign_in_dart: ^0.0.1
    ```
1. Run `flutter pub get`
1. Import
    ```dart
    import 'package:google_sign_in/google_sign_in.dart';
    import 'package:google_sign_in_dart/google_sign_in_dart.dart';
    ```        
1. Register the package
    ```dart 
    import 'package:flutter/material.dart';
    import 'package:google_sign_in/google_sign_in.dart';
    import 'package:google_sign_in_dart/google_sign_in_dart.dart';
    
    void main() {
      if (isDesktop) {
        GoogleSignInPlatform.register(clientId: <clientId>);
      }
    
      runApp(MyApp());
    }
    ``` 
    Note: You might want to `await` for the `register` method to finish before calling any `GoogleSignIn` methods when your app starts.  

###  Usage
You can use the normal `GoogleSignIn` methods.
```dart 
final GoogleSignInAccount account = await GoogleSignIn().signIn();
```

## Obtain a Client ID for your Desktop app
1. Go to the Google Cloud Platform console and select you [project](https://console.cloud.google.com/projectselector2/home/dashboard) 
1. Go to `APIs & Service` -> `Credentials`
1. Create new credentials for your app by selecting `CREATE CREDENTIALS` and then `OAuth client ID`
1. Select `Other` as `Application type`, give it a name (eg. macOS) and then click `Create`

### Provide a code exchange endpoint
The user accessToken expires after about one hour, after witch you need to ask the user to login again. If you want to 
keep the user logged in you need to deploy a code exchange endpoint.   
