library firebase_core;

export 'package:_firebase_internal_vm/src/auth.dart' show GetTokenResult;
export 'package:_firebase_internal_vm/src/internal.dart'
    show InternalTokenProvider, InternalTokenResult;

export 'src/firebase_app.dart';
export 'src/firebase_error.dart';
export 'src/firebase_options.dart';
export 'src/platform_js.dart' if (dart.library.io) 'src/platform_io.dart';
