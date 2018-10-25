// File created by
// Lung Razvan <long1eu>
// on 22/10/2018

import 'dart:async';

import 'package:firebase_storage/src/future_handle.dart';
import 'package:firebase_storage/src/util/wrapped_future.dart';

class FutureHandleImpl<TState> extends WrappedFuture<TState>
    implements FutureHandler<TState> {
  final void Function(dynamic) _send;
  final Stream<dynamic> _received;

  int _id = 0;

  FutureHandleImpl(this._send, this._received);

  @override
  Future<bool> cancel() => _callMethod('cancel');

  @override
  Future<bool> pause() => _callMethod('pause');

  @override
  Future<bool> resume() => _callMethod('resume');

  @override
  Future<bool> get isCanceled => _callMethod('isCanceled');

  @override
  Future<bool> get isInProgress => _callMethod('isInProgress');

  @override
  Future<bool> get isPaused => _callMethod('isPaused');

  Future<bool> _callMethod(String method) async {
    final int id = ++_id;
    _send(<dynamic>[id, method]);

    final bool result = (await _received
        .where((dynamic it) => it[0] == id && it[1] == method)
        .first)[2];
    return result;
  }
}
