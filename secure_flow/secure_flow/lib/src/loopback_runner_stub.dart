import 'package:secure_flow/src/flow.dart';
import 'package:secure_flow/src/presenter.dart';

/// The loopback server needs `dart:io`; on this platform it throws an [UnsupportedError].
Future<T> runOnLoopback<T>(
  SecureFlow<T> flow,
  LoopbackPresenter presenter, {
  required Duration timeout,
  Future<void>? cancel,
}) async => throw UnsupportedError(
  'The loopback server of secure_flow needs dart:io (desktop and command line).',
);
