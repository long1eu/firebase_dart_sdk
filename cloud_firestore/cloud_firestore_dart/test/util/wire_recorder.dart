// Records what the clients of a test send and receive, for the failure output of the chaos tests: every stream
// start and end (so the restarts), the write batches in the order each client sends them with the commit and
// update times of their acknowledgements, and what watch delivers. Nothing in the library changes: the recorder
// wraps the transport of each client (IntegrationTestUtil.transportDecorator).

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:grpc/grpc.dart' show CallOptions, GrpcError;
import 'package:protobuf/protobuf.dart';

import 'integration_test_util.dart';

/// Records the calls of every client created while it is installed.
class WireRecorder {
  WireRecorder(this._clock);

  /// The clock of the test, so that the lines can be read next to its own log.
  final Stopwatch _clock;

  final List<String> log = <String>[];

  /// Names of the clients by the port they connect to (the port of their proxy).
  final Map<int, String> names = <int, String>{};

  int _calls = 0;

  /// Records the clients created from now on, until [uninstall].
  void install() {
    IntegrationTestUtil.transportDecorator =
        (FirestoreTransport transport, DatabaseInfo info) =>
            _RecordingTransport(transport, this, info.port);
  }

  void uninstall() => IntegrationTestUtil.transportDecorator = null;

  void _add(int port, String message) {
    log.add('${_clock.elapsedMilliseconds.toString().padLeft(6)} '
        '${names[port] ?? 'port $port'} $message');
  }

  /// The lines about [ids] (document ids), and all the lines about streams starting and ending.
  List<String> about(Set<String> ids) => <String>[
        for (final String line in log)
          if (line.contains(' start') ||
              line.contains(' end') ||
              ids.any((String id) => line.contains('$id ') || line.contains('$id{')))
            line,
      ];
}

class _RecordingTransport implements FirestoreTransport {
  _RecordingTransport(this._inner, this._recorder, this._port);

  final FirestoreTransport _inner;
  final WireRecorder _recorder;
  final int _port;

  @override
  ResponseStream<Res>
      startCall<Req extends GeneratedMessage, Res extends GeneratedMessage>(
          FirestoreRpc<Req, Res> rpc, Stream<Req> requests,
          {CallOptions? options}) {
    final String call = '${rpc.name}#${_recorder._calls++}';
    void add(String message) => _recorder._add(_port, '$call $message');
    add('start');
    final ResponseStream<Res> responses = _inner.startCall(
      rpc,
      requests.map((Req request) {
        final String? text = _describe(request);
        if (text != null) {
          add('> $text');
        }
        return request;
      }),
      options: options,
    );
    final Stream<Res> recorded = responses.transform(
      StreamTransformer<Res, Res>.fromHandlers(
        handleData: (Res response, EventSink<Res> sink) {
          final String? text = _describe(response);
          if (text != null) {
            add('< $text');
          }
          sink.add(response);
        },
        handleError: (Object error, StackTrace stackTrace, EventSink<Res> sink) {
          add('end with ${error is GrpcError ? '${error.codeName} ${error.message}' : error}');
          sink.addError(error, stackTrace);
        },
        handleDone: (EventSink<Res> sink) {
          add('end');
          sink.close();
        },
      ),
    );
    return ResponseStream<Res>(responses, recorded);
  }

  @override
  Future<void> shutdown() => _inner.shutdown();
}

String _time(proto.Timestamp time) {
  if (time.seconds == 0 && time.nanos == 0) {
    return '-';
  }
  // Enough to order the versions of one run: the seconds within a day and the microseconds.
  final int seconds = time.seconds.toInt() % 86400;
  return '$seconds.${(time.nanos ~/ 1000).toString().padLeft(6, '0')}';
}

String _id(String name) => name.substring(name.lastIndexOf('/') + 1);

String _value(pb.Value value) {
  switch (value.whichValueType()) {
    case pb.Value_ValueType.integerValue:
      return '${value.integerValue}';
    case pb.Value_ValueType.doubleValue:
      return '${value.doubleValue}';
    case pb.Value_ValueType.booleanValue:
      return '${value.booleanValue}';
    case pb.Value_ValueType.stringValue:
      return '"${value.stringValue}"';
    case pb.Value_ValueType.nullValue:
      return 'null';
    case pb.Value_ValueType.arrayValue:
      return '[${value.arrayValue.values.map(_value).join(',')}]';
    case pb.Value_ValueType.mapValue:
      return _fields(value.mapValue.fields);
    default:
      return value.whichValueType().name;
  }
}

String _fields(Map<String, pb.Value> fields) {
  final List<String> keys = fields.keys.toList()..sort();
  return '{${keys.map((String key) => '$key:${_value(fields[key]!)}').join(',')}}';
}

String _write(pb.Write write) {
  final StringBuffer buffer = StringBuffer();
  if (write.hasUpdate()) {
    buffer.write(
        '${write.hasUpdateMask() ? 'patch[${write.updateMask.fieldPaths.join(',')}]' : 'set'} '
        '${_id(write.update.name)}${_fields(write.update.fields)}');
  } else if (write.hasDelete()) {
    buffer.write('delete ${_id(write.delete)} ');
  } else if (write.hasVerify()) {
    buffer.write('verify ${_id(write.verify)} ');
  }
  for (final pb.DocumentTransform_FieldTransform transform
      in write.updateTransforms) {
    buffer.write(' transform ${transform.fieldPath}=');
    if (transform.hasIncrement()) {
      buffer.write('increment(${_value(transform.increment)})');
    } else if (transform.hasAppendMissingElements()) {
      buffer.write(
          'union[${transform.appendMissingElements.values.map(_value).join(',')}]');
    } else if (transform.hasRemoveAllFromArray()) {
      buffer.write(
          'remove[${transform.removeAllFromArray.values.map(_value).join(',')}]');
    } else {
      buffer.write('other');
    }
  }
  if (write.hasCurrentDocument()) {
    buffer.write(write.currentDocument.hasExists()
        ? ' if exists=${write.currentDocument.exists}'
        : ' if updateTime=${_time(write.currentDocument.updateTime)}');
  }
  return buffer.toString();
}

String _results(List<pb.WriteResult> results) => results
    .map((pb.WriteResult result) => '${_time(result.updateTime)}'
        '${result.transformResults.isEmpty ? '' : ' transformResults ${result.transformResults.map(_value).join(',')}'}')
    .join('; ');

String _targetIds(List<int> ids) => ids.isEmpty ? 'all' : ids.join(',');

/// A line for [message], or null for a message that says nothing (a handshake, for example).
String? _describe(GeneratedMessage message) {
  if (message is pb.WriteRequest) {
    return message.writes.isEmpty
        ? 'handshake'
        : 'batch: ${message.writes.map(_write).join(' | ')}';
  } else if (message is pb.WriteResponse) {
    return message.writeResults.isEmpty && !message.hasCommitTime()
        ? 'handshake'
        : 'ack commit=${_time(message.commitTime)} updates: ${_results(message.writeResults)}';
  } else if (message is pb.CommitRequest) {
    return 'commit: ${message.writes.map(_write).join(' | ')}';
  } else if (message is pb.CommitResponse) {
    return 'committed commit=${_time(message.commitTime)} updates: ${_results(message.writeResults)}';
  } else if (message is pb.ListenRequest) {
    if (message.hasAddTarget()) {
      final pb.Target target = message.addTarget;
      return 'addTarget ${target.targetId} '
          '${target.hasQuery() ? 'query' : 'documents ${target.documents.documents.map(_id).join(',')}'}'
          '${target.resumeToken.isEmpty ? '' : ' resume'}'
          '${target.hasReadTime() ? ' readTime=${_time(target.readTime)}' : ''}'
          '${target.hasExpectedCount() ? ' expectedCount=${target.expectedCount.value}' : ''}';
    }
    return 'removeTarget ${message.removeTarget}';
  } else if (message is pb.ListenResponse) {
    if (message.hasTargetChange()) {
      final pb.TargetChange change = message.targetChange;
      return 'target ${change.targetChangeType.name} ${_targetIds(change.targetIds)}'
          '${change.hasReadTime() ? ' readTime=${_time(change.readTime)}' : ''}'
          '${change.resumeToken.isEmpty ? '' : ' token'}'
          '${change.hasCause() ? ' cause=${change.cause.code} ${change.cause.message}' : ''}';
    } else if (message.hasDocumentChange()) {
      final pb.DocumentChange change = message.documentChange;
      return 'doc ${_id(change.document.name)}${_fields(change.document.fields)} '
          'updateTime=${_time(change.document.updateTime)} '
          'targets=${change.targetIds.join(',')} removed=${change.removedTargetIds.join(',')}';
    } else if (message.hasDocumentDelete()) {
      return 'deleted ${_id(message.documentDelete.document)} '
          'readTime=${_time(message.documentDelete.readTime)} '
          'removed=${message.documentDelete.removedTargetIds.join(',')}';
    } else if (message.hasDocumentRemove()) {
      return 'removed ${_id(message.documentRemove.document)} '
          'removed=${message.documentRemove.removedTargetIds.join(',')}';
    } else if (message.hasFilter()) {
      return 'filter target=${message.filter.targetId} count=${message.filter.count}';
    }
    return 'listen response';
  } else if (message is pb.BatchGetDocumentsRequest) {
    return 'get ${message.documents.map(_id).join(',')}';
  } else if (message is pb.BatchGetDocumentsResponse) {
    return message.hasFound()
        ? 'found ${_id(message.found.name)}${_fields(message.found.fields)} '
            'updateTime=${_time(message.found.updateTime)}'
        : 'missing ${_id(message.missing)} readTime=${_time(message.readTime)}';
  }
  return message.info_.messageName.split('.').last;
}
