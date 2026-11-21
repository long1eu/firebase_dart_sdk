import 'package:secure_flow/src/environment_stub.dart'
    if (dart.library.io) 'package:secure_flow/src/environment_io.dart';
import 'package:secure_flow/src/flow.dart';
import 'package:secure_flow/src/presenter.dart';
import 'package:secure_flow/src/presenters_stub.dart'
    if (dart.library.io) 'package:secure_flow/src/presenters_io.dart';

/// What a flow can choose from when no presenter is given ([SecureFlow.run]): the presenters this
/// environment offers. Injected, so that the choice can be tested without the real environment.
final class SecureEnvironment {
  /// An environment: [operatingSystem] is a value of `Platform.operatingSystem` (`macos`,
  /// `linux`, `windows`, `android`, `ios`, `fuchsia`) or `web`; [variables] are the environment
  /// variables; [hasTerminal] says whether a person can read and type at a terminal;
  /// [registered] are the presenters the app adds (a provider app, an in-app browser, ...).
  const SecureEnvironment({
    required this.operatingSystem,
    this.variables = const <String, String>{},
    this.hasTerminal = false,
    this.registered = const <SecurePresenter>[],
  });

  /// The environment of this program: `Platform.operatingSystem`, `Platform.environment`, and
  /// whether stdin and stderr are terminals, with [registered]. On the web, `web` and
  /// [registered] only.
  factory SecureEnvironment.current({
    List<SecurePresenter> registered = const <SecurePresenter>[],
  }) => currentEnvironment(registered);

  /// The operating system.
  final String operatingSystem;

  /// The environment variables.
  final Map<String, String> variables;

  /// Whether stdin and stderr are terminals.
  final bool hasTerminal;

  /// The presenters the app adds.
  final List<SecurePresenter> registered;

  /// Whether this is an SSH session (`SSH_CONNECTION` or `SSH_TTY` is set): a browser opened here
  /// would open on the remote machine, or nowhere.
  bool get isSsh => _isSet('SSH_CONNECTION') || _isSet('SSH_TTY');

  /// Whether a system browser can be shown: a desktop system, not over SSH, and on Linux an X11 or
  /// Wayland display (`DISPLAY` or `WAYLAND_DISPLAY`).
  bool get hasDisplay => switch (operatingSystem) {
    'macos' || 'windows' => !isSsh,
    'linux' => !isSsh && (_isSet('DISPLAY') || _isSet('WAYLAND_DISPLAY')),
    _ => false,
  };

  /// The presenters on offer: [registered] first, then a `SystemBrowserPresenter` when there is a
  /// display, then a `ConsolePresenter` when there is a terminal. A flow ranks them by kind
  /// ([SecureFlow.presenterKinds]); the order here only matters between two of one kind.
  List<SecurePresenter> get presenters => <SecurePresenter>[
    ...registered,
    if (hasDisplay) const SystemBrowserPresenter(),
    if (hasTerminal) ConsolePresenter(),
  ];

  bool _isSet(String name) => variables[name]?.isNotEmpty ?? false;

  @override
  String toString() =>
      'SecureEnvironment($operatingSystem, ssh: $isSsh, display: $hasDisplay, '
      'terminal: $hasTerminal, registered: ${registered.length})';
}
