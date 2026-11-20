import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage, InMemoryAuthStorage;

/// No file system here: there is no default file.
String? defaultSessionFile() => null;

/// Memory: the user signs in again after a restart.
AuthStorage defaultFileStorage() => InMemoryAuthStorage();

/// No file system here: never a file error.
bool isFileSystemException(Object error) => false;

/// No environment here: never under `flutter test`.
bool runningUnderFlutterTest() => false;
