import 'package:secure_flow/src/environment.dart';
import 'package:secure_flow/src/presenter.dart';

/// The environment of a program without `dart:io` (the web), with [registered].
SecureEnvironment currentEnvironment(List<SecurePresenter> registered) =>
    SecureEnvironment(operatingSystem: 'web', registered: registered);
