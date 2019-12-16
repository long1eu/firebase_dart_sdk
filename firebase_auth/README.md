# Firebase Auth Dart SDK - CLI example app

## Install
All needed dependencies are provided by the [PlatformDependencies]. The current implementation uses hive to store the 
current user and his tokens.

```dart
class Dependencies extends PlatformDependencies {
  Dependencies({@required this.box}) : headersBuilder = null;

  @override
  final Box<dynamic> box;

  @override
  final HeaderBuilder headersBuilder;

  @override
  InternalTokenProvider get authProvider => null;

  @override
  AuthUrlPresenter get authUrlPresenter => null;

  @override
  bool get isBackground => false;

  @override
  Future<bool> get isNetworkConnected => Future<bool>.value(true);

  @override
  String get locale => 'en';

  @override
  Stream<bool> get isBackgroundChanged => Stream<bool>.fromIterable(<bool>[false]);
}

```

## Initialize
You just need to initialize you're FirebaseApp then you are ready to go.
```dart
  final Box<dynamic> firebaseBox =
      await Hive.openBox<dynamic>('firebase_auth', encryptionKey: _hiveEncryptionKey.codeUnits);
  final Dependencies dependencies = Dependencies(box: firebaseBox);
  final FirebaseOptions options = FirebaseOptions(apiKey: _apiKey, applicationId: 'appId');
  FirebaseApp.withOptions(options, dependencies);
```
After this you can use `FirebaseAuth.instance` for the default Firebase App or `FirebaseAuth.getInstance(FirebaseApp app)` for a specify Firebase App.

##Disclaimer
This is still under heavy development and it still has some roughs edges. Please make sure to open an issue or a pull request if you found something. Thanks :D