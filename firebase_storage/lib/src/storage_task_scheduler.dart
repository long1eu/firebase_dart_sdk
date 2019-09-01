// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'dart:async';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:isolate/isolate.dart';
import 'package:meta/meta.dart';

final Map<String, SendPort> _sendPorts = <String, SendPort>{};
final Map<int, String> _sendPortsHashes = <int, String>{};

/// A class used to schedule long running operations (upload/download) and
/// operations that are intended to be short lived (list/get/delete)
class StorageTaskScheduler {
  StorageTaskScheduler._();

  static StorageTaskScheduler instance = StorageTaskScheduler._();

  LoadBalancer _commands;
  LoadBalancer _uploads;
  LoadBalancer _downloads;
  LoadBalancer _callback;

  /// We should call this only after we've initialized all the FirebaseApps.
  // TODO:{24/10/2018 09:36}-long1eu: if we decide we can add apps as we go we
  // need to provide a way to let the isolates now we have a new FirebaseApp
  static Future<void> initialize() async {
    int _iCommands = 0;
    int _iUploads = 0;
    int _iDownloads = 0;
    int _iCallback = 0;

    final ReceivePort servicePort = ReceivePort()
      ..listen((dynamic data) async {
        //Log.d('MAIN', data);
        if (data is _IsolateCallPayload) {
          switch (data.methodName) {
            case 'getAccessToken':
              final bool forceRefresh = data.argument;
              final GetTokenResult result =
                  await FirebaseApp.getInstance(data.appName)
                      .getAuthProvider
                      .getAccessToken(forceRefresh);

              _sendPorts[data.runnerName]
                  .send(_IsolateCallPayload<Map<String, dynamic>>(
                runnerName: data.runnerName,
                appName: data.appName,
                methodName: data.methodName,
                argument: result.toJson(),
              ));
              break;
            case 'isNetworkConnected':
              final bool result = await FirebaseApp.getInstance(data.appName)
                  .isNetworkConnected();

              _sendPorts[data.runnerName].send(_IsolateCallPayload<bool>(
                runnerName: data.runnerName,
                appName: data.appName,
                methodName: data.methodName,
                argument: result,
              ));
              break;
            default:
              throw StateError(
                  'Received a call with a method that is not implemented: '
                  '$data');
          }
        } else if (data is List<dynamic> &&
            data.length == 3 &&
            data[1] is SendPort) {
          final String runnerName = data[0];
          final SendPort sendPort = data[1];
          _sendPorts[runnerName] = sendPort;
        }
      });

    Future<IsolateRunner> createIsolate(String runnerName) async {
      final Map<String, Map<String, String>> appOptions =
          FirebaseApp.instances.map((String appName, FirebaseApp app) {
        return MapEntry<String, Map<String, String>>(
            appName, app.options.toJson());
      });

      final IsolateRunner runner = await IsolateRunner.spawn();
      await runner.run(_serviceCalls, <dynamic>[
        runnerName,
        servicePort.sendPort,
        appOptions,
      ]);
      return runner;
    }

    instance._commands = await LoadBalancer.create(
        5, () => createIsolate('commands-${_iCommands++}'));
    instance._uploads = await LoadBalancer.create(
        2, () => createIsolate('uploads-${_iUploads++}'));
    instance._downloads = await LoadBalancer.create(
        3, () => createIsolate('downloads-${_iDownloads++}'));
    instance._callback = await LoadBalancer.create(
        1, () => createIsolate('callback-${_iCallback++}'));
  }

  Future<R> scheduleCommand<R, P>(Future<R> function(P argument), P argument) {
    return _commands.run(function, argument);
  }

  Future<R> scheduleUpload<R, P>(Future<R> function(P argument), P argument) {
    return _uploads.run(function, argument);
  }

  Future<R> scheduleDownload<R, P>(Future<R> function(P argument), P argument) {
    return _downloads.run(function, argument);
  }

  Future<R> scheduleCallback<R, P>(Future<R> function(P argument), P argument) {
    return _callback.run(function, argument);
  }
}

void _serviceCalls(List<dynamic> args) {
  final String runnerName = args[0];
  _sendPortsHashes[Isolate.current.hashCode] = runnerName;

  final SendPort sendPort = args[1];
  final Map<String, Map<String, String>> appsOptions = args[2];
  final ReceivePort receivePort = ReceivePort();
  final Stream<List<dynamic>> receiveStream =
      receivePort.cast<List<dynamic>>().asBroadcastStream();

  final IsolateRunnerProxy proxy = IsolateRunnerProxy(
      runnerName: runnerName,
      appName: '',
      sendPort: sendPort,
      receiveStream: receiveStream);

  for (String appName in appsOptions.keys) {
    final Map<String, String> options = appsOptions[appName];

    FirebaseApp(
      options,
      _IsolateTokenProvider(proxy.copyWith(appName: appName)),
      _IsolateIsNetworkConnected(proxy.copyWith(appName: appName)),
    );
  }

  sendPort.send(
      <dynamic>[runnerName, receivePort.sendPort, Isolate.current.hashCode]);
}

class _IsolateTokenProvider extends IsolateRunnerProxy
    implements InternalTokenProvider {
  _IsolateTokenProvider(IsolateRunnerProxy proxy)
      : super(
          runnerName: proxy.runnerName,
          appName: proxy.appName,
          sendPort: proxy.sendPort,
          receiveStream: proxy.receiveStream,
        );

  @override
  Future<GetTokenResult> getAccessToken(bool forceRefresh) async {
    sendPort.send(_IsolateCallPayload<bool>(
      runnerName: runnerName,
      appName: appName,
      methodName: 'getAccessToken',
      argument: forceRefresh,
    ));

    return await (_forMethod<Map<String, dynamic>>('getAccessToken')
            .map((Map<String, dynamic> it) => GetTokenResult.fromJson(it)))
        .first;
  }

  @override
  Stream<InternalTokenResult> get onTokenChanged {
    throw StateError('This method is not implemented for Firebase Storage.');
  }

  @override
  String get uid {
    throw StateError('This method is not implemented for Firebase Storage.');
  }

  Stream<T> _forMethod<T>(String methodName) {
    return receiveStream
        .where((List<dynamic> it) =>
            it is _IsolateCallPayload &&
            it.methodName == methodName &&
            it.appName == appName &&
            it.runnerName == runnerName)
        .cast<_IsolateCallPayload<T>>()
        .map((_IsolateCallPayload<T> it) => it.argument);
  }
}

class _IsolateIsNetworkConnected extends IsolateRunnerProxy {
  _IsolateIsNetworkConnected(IsolateRunnerProxy proxy)
      : super(
          runnerName: proxy.runnerName,
          appName: proxy.appName,
          sendPort: proxy.sendPort,
          receiveStream: proxy.receiveStream,
        );

  Future<bool> call() async {
    sendPort.send(_IsolateCallPayload<void>(
      runnerName: runnerName,
      appName: appName,
      methodName: 'isNetworkConnected',
    ));

    return await (receiveStream
            .where((List<dynamic> it) =>
                it is _IsolateCallPayload &&
                it.methodName == 'isNetworkConnected' &&
                it.appName == appName &&
                it.runnerName == runnerName)
            .cast<_IsolateCallPayload<bool>>()
            .map((_IsolateCallPayload<bool> it) => it.argument))
        .first;
  }
}

class IsolateRunnerProxy {
  IsolateRunnerProxy({
    @required this.runnerName,
    @required this.appName,
    @required this.sendPort,
    @required this.receiveStream,
  });

  final String runnerName;
  final String appName;
  final SendPort sendPort;
  final Stream<List<dynamic>> receiveStream;

  IsolateRunnerProxy copyWith({
    String runnerName,
    String appName,
    SendPort sendPort,
    Stream<List<dynamic>> receiveStream,
  }) {
    return IsolateRunnerProxy(
      runnerName: runnerName ?? this.runnerName,
      appName: appName ?? this.appName,
      sendPort: sendPort ?? this.sendPort,
      receiveStream: receiveStream ?? this.receiveStream,
    );
  }
}

class _IsolateCallPayload<T> extends DelegatingList<dynamic> {
  _IsolateCallPayload({
    @required this.runnerName,
    @required this.appName,
    @required this.methodName,
    this.argument,
  }) : super(<dynamic>[runnerName, appName, methodName, argument]);

  final String runnerName;
  final String appName;
  final String methodName;
  final T argument;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('runnerName', runnerName)
          ..add('appName', appName)
          ..add('methodName', methodName)
          ..add('argument', argument))
        .toString();
  }
}
