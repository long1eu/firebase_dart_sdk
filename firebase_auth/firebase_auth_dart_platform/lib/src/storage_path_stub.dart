/// No file system here: there is no default file.
String? defaultSessionFile() => null;

/// No file system here: never a file error.
bool isFileSystemException(Object error) => false;

/// No environment here: never under `flutter test`.
bool runningUnderFlutterTest() => false;
