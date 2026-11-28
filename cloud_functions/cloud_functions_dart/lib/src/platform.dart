/// Compile-time facts about the platform the client runs on.
library;

/// True when compiled for a browser (dart2js or dart2wasm).
///
/// Used only to add the CORS sentence to the message of a transport failure (§5.8).
const bool isWeb = bool.fromEnvironment('dart.library.js_interop');

/// True on the JS-number platform (dart2js), where `int` and `double` are both JavaScript numbers.
///
/// There a 64-bit wrapper beyond 2^53 − 1 cannot be held exactly and is refused (§5.6).
const bool jsNumbers = identical(0, 0.0);
