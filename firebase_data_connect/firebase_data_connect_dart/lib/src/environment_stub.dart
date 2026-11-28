/// The environment where `dart:io` is missing, which is the web.
///
/// The default branch of the conditional import that picks `environment_io.dart` on the VM.
library;

/// Always null: the web has no environment variables. [name] is not read.
String? environmentVariable(String name) => null;

/// Always false: a browser is never the Android platform this flag is about.
bool get isAndroid => false;

/// Always true: without `dart:io` the code runs in a browser.
bool get isWeb => true;
