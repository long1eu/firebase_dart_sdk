import 'package:meta/meta.dart';

/// The options of the Auth emulator, the `options` of `connectAuthEmulator` in the JS SDK
/// (`packages/auth/src/core/auth/emulator.ts:48`).
@immutable
class AuthEmulatorOptions {
  /// Creates the options.
  const AuthEmulatorOptions({this.disableWarnings = false});

  /// Whether the warning about an emulator off the loopback interface is left out of the log. The JS SDK uses
  /// the same option to leave out its warning for every emulator (`emulator.ts:57`, `:103`).
  final bool disableWarnings;

  @override
  bool operator ==(Object other) =>
      other is AuthEmulatorOptions && other.disableWarnings == disableWarnings;

  @override
  int get hashCode => disableWarnings.hashCode;

  @override
  String toString() => 'AuthEmulatorOptions(disableWarnings: $disableWarnings)';
}

/// The Auth emulator a `FirebaseUserAuth` talks to, like `auth.emulatorConfig` of the JS SDK
/// (`packages/auth/src/core/auth/emulator.ts:65-70`).
@immutable
class AuthEmulatorConfig {
  /// Creates the configuration.
  const AuthEmulatorConfig({
    required this.protocol,
    required this.host,
    this.port,
    this.options = const AuthEmulatorOptions(),
  });

  /// `http` or `https`, without the colon.
  final String protocol;

  /// The host as it was given; an IPv6 address keeps its brackets (`[::1]`), like `extractHostAndPort` of the
  /// JS SDK (`emulator.ts:113-131`).
  final String host;

  /// The port, or null when none was given.
  final int? port;

  /// The options the emulator was configured with.
  final AuthEmulatorOptions options;

  @override
  bool operator ==(Object other) =>
      other is AuthEmulatorConfig &&
      other.protocol == protocol &&
      other.host == host &&
      other.port == port &&
      other.options == options;

  @override
  int get hashCode => Object.hash(protocol, host, port, options);

  @override
  String toString() =>
      'AuthEmulatorConfig(protocol: $protocol, host: $host, port: $port, options: $options)';
}
