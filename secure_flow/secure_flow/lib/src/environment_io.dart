import 'dart:io';

import 'package:secure_flow/src/environment.dart';
import 'package:secure_flow/src/presenter.dart';

/// The environment of this program, with [registered].
SecureEnvironment currentEnvironment(List<SecurePresenter> registered) =>
    SecureEnvironment(
      operatingSystem: Platform.operatingSystem,
      variables: Platform.environment,
      hasTerminal: stdin.hasTerminal && stderr.hasTerminal,
      registered: registered,
    );
