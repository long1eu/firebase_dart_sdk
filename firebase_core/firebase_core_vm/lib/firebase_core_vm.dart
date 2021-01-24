library firebase_core_vm;

export 'package:_firebase_internal_vm/src/auth.dart' show GetTokenResult;
export 'package:_firebase_internal_vm/src/internal.dart' show InternalTokenProvider, InternalTokenResult;

export 'src/emulators/emulated_service_settings.dart';
export 'src/firebase_app.dart';
export 'src/firebase_error.dart';
export 'src/firebase_options.dart';
export 'src/heart_beat/default_heart_beat_info.dart';
export 'src/heart_beat/heart_beat_info.dart';
export 'src/heart_beat/heart_beat_info_storage.dart';
export 'src/heart_beat/heart_beat_result.dart';
export 'src/heart_beat/sdk_heart_beat_result.dart';
export 'src/platform_js.dart' if (dart.library.io) 'src/platform_io.dart';
