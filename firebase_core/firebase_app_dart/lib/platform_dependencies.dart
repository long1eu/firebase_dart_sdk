/// The services a [FirebaseApp] needs from the platform it runs on.
///
/// Subclass [PlatformDependencies] and pass it to `FirebaseApp.withOptions` to
/// provide persistent storage, connectivity and background signals, extra
/// request headers, and auth or App Check tokens.
library platform_dependencies;

export 'src/platform_dependencies.dart';
