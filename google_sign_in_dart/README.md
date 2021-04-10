# google_sign_in_dartio

A Flutter package that implements [Google Sign In](https://developers.google.com/identity/)
in pure Dart. This package is compatible with `google_sign_in` plugin
and works on all platforms Flutter supports but it's intended to be
mainly used on Desktop.

## Getting Started

### Install and initialization
1. Depend on it
    ```yaml
    dependencies:
      google_sign_in: ^4.1.4
      google_sign_in_dartio: ^0.0.6
    ```
1. Run `flutter pub get`
1. Import
    ```dart
    import 'package:google_sign_in_dartio/google_sign_in_dartio.dart';
    ```        
1. Register the package
    ```dart
    Future<void> main() async {
      if (isDesktop) {
        await GoogleSignInDart.register(clientId: <clientId>);
      }
    
      runApp(MyApp());
    }
    ``` 
    Note: You should ensure the `register` method completes before calling any `GoogleSignIn` methods when your app starts. 

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
The user `accessToken` expires after about one hour, after witch you need to ask the user to login again. If you want to 
keep the user logged in, you need to deploy a oAuth code exchange endpoint. Once you have your endpoint you can register
the package like this. 

    import 'package:flutter/material.dart';
    import 'package:google_sign_in_dartio/google_sign_in_dartio.dart';
    
    Future<void> main() async {
      if (isDesktop) {
        await GoogleSignInDart.register(
            clientId: <clientId>, 
            exchangeEndpoint: <endpoint>,
        );
      }
    
      runApp(MyApp());
    }

#### NOTE:
`GoogleSignInTokenData` exposes `serverAuthCode` field that should
contain the exchange code from the authorization request. This will
always be null when using this package because we already allow you to
provide a code exchange endpoint witch exposes the code and code
verifier in a trusted environment and encourages not to do the code
exchange on the client.

See instruction on how to [deploy a code exchange endpoint](https://github.com/fluttercommunity/firebase_dart_sdk/tree/develop/google_sign_in_dart/example/gcp).    
