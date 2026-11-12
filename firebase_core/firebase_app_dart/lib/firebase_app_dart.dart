library firebase_app_dart;

export 'src/firebase_app.dart';
export 'src/firebase_error.dart';
export 'src/firebase_options.dart';
export 'src/internal/app_check.dart'
    show AppCheckTokenResult, InternalAppCheckTokenProvider;
export 'src/internal/auth.dart' show GetTokenResult;
export 'src/internal/internal.dart'
    show InternalTokenProvider, InternalTokenResult;
export 'src/platform_js.dart' if (dart.library.io) 'src/platform_io.dart';
