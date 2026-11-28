import 'dart:async';

import 'package:firebase_ai_dart/src/aggregate.dart';
import 'package:firebase_ai_dart/src/content.dart';
import 'package:firebase_ai_dart/src/generative_model.dart';
import 'package:firebase_ai_dart/src/request.dart';
import 'package:firebase_ai_dart/src/response.dart';
import 'package:firebase_ai_dart/src/validation.dart';

/// A conversation with a model: each send carries the history followed by the new message.
///
/// Created by `GenerativeModel.startChat`. Each request carries the model's tools, tool
/// configuration and system instruction, and the chat's safety settings and generation
/// configuration.
///
/// **Sends are serialized.** A send starts only after the previous one finished, whether it
/// completed, failed, was cancelled or timed out. [sendMessage] takes its place in the queue when
/// it is called; [sendMessageStream] when its stream is listened to, so a stream that is never
/// listened to blocks nothing. A call's `timeout` and `abortTrigger` count from the call, including
/// the time it waits in the queue. A paused stream keeps its place and its idle timers stop:
/// cancel, rather than pause, a stream the app no longer reads.
///
/// **History.** The message and the reply are appended together, and only when the reply's first
/// candidate has at least one part and no blocking finish reason (replies ending in `MAX_TOKENS` or
/// `OTHER` are appended). After an exception, a cancel, a timeout, a blocked prompt or a blocked
/// candidate, the history is unchanged. The history lives in memory only, and the client keeps
/// every turn: each turn resends the whole history, so long chats grow in cost; start a new chat
/// from a trimmed or summarized [history] when it grows.
final class ChatSession {
  ChatSession._(this._core, this._history, this._settings);

  final ModelCore _core;
  final List<Content> _history;
  final RequestSettings _settings;
  Future<void> _tail = Future<void>.value();

  /// An unmodifiable copy of the history.
  List<Content> get history => List<Content>.unmodifiable(_history);

  /// Sends [message] after the history and returns the reply.
  ///
  /// [message] has role `user` (null counts as `user`), at least one part, and either only
  /// function-response parts or none. Throws [ArgumentError] otherwise, or for a negative
  /// [timeout]; `FirebaseAIException` for every failure of the call. [timeout] and [abortTrigger]
  /// are those of `GenerativeModel.generateContent`.
  Future<GenerateContentResponse> sendMessage(
    Content message, {
    Duration? timeout,
    Future<void>? abortTrigger,
  }) async {
    final Content user = _checkedMessage(message);
    final AiCall call = _core.startCall(timeout, abortTrigger);
    final _Slot slot = _takeSlot();
    try {
      await _waitForTurn(slot, call);
      final List<Content> contents = <Content>[..._history, user];
      final GenerateContentResponse response = await _core.generate(
        contents,
        _settings,
        call,
      );
      _appendTurn(user, response);
      return response;
    } finally {
      slot.release();
    }
  }

  /// Sends [message] after the history and returns the reply as a stream of chunks.
  ///
  /// The checks of [sendMessage] are made before this method returns, and their errors are thrown
  /// synchronously. Nothing is sent, and no place in the queue is taken, until the stream is
  /// listened to. The history is updated from the aggregate of the chunks once the stream ended
  /// without error. The rest is as for `GenerativeModel.generateContentStream`.
  Stream<GenerateContentResponse> sendMessageStream(
    Content message, {
    Duration? timeout,
    Future<void>? abortTrigger,
  }) {
    final Content user = _checkedMessage(message);
    final AiCall call = _core.startCall(timeout, abortTrigger);
    return _ChatStream(this, user, call, timeout).stream;
  }

  Content _checkedMessage(Content message) {
    checkMessage(message);
    return message.role == null ? Content('user', message.parts) : message;
  }

  /// Takes the next place in the queue: it starts when every earlier place was released.
  _Slot _takeSlot() {
    final Future<void> previous = _tail;
    final Completer<void> done = Completer<void>();
    _tail = previous.then((void _) => done.future);
    return _Slot(previous, done);
  }

  /// Waits until [slot] starts, failing early when [call] ends first (its deadline, its abort
  /// trigger, or the instance closing). A call that fails here is disposed.
  Future<void> _waitForTurn(_Slot slot, AiCall call) async {
    try {
      call.throwIfEnded();
      await Future.any(<Future<void>>[slot.turn, call.whenEnded]);
      call.throwIfEnded();
    } on Object {
      call.dispose();
      rethrow;
    }
  }

  void _appendTurn(Content user, GenerateContentResponse response) {
    if (!canAppendTurn(response)) {
      return;
    }
    final Candidate first = response.candidates.first;
    _history
      ..add(user)
      ..add(Content(first.content.role ?? 'model', first.content.parts));
  }
}

/// Creates a [ChatSession] of [core]; used by `GenerativeModel.startChat`.
ChatSession newChatSession(
  ModelCore core, {
  required List<Content> history,
  required RequestSettings settings,
}) => ChatSession._(core, history, settings);

/// One place in a chat's queue.
final class _Slot {
  _Slot(this.turn, this._done);

  /// Completes when every earlier place was released.
  final Future<void> turn;
  final Completer<void> _done;

  /// Lets the next place start once the earlier ones are released too. Idempotent.
  void release() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

/// The stream of one [ChatSession.sendMessageStream] call.
///
/// It takes its place in the queue when listened to, forwards the model's chunks, pause and
/// cancel, and appends the turn from the aggregate when the model's stream ends without error.
final class _ChatStream {
  _ChatStream(this._chat, this._message, this._call, this._timeout) {
    _controller = StreamController<GenerateContentResponse>(
      onListen: _onListen,
      onPause: () => _inner?.pause(),
      onResume: () => _inner?.resume(),
      onCancel: _onCancel,
      sync: true,
    );
  }

  final ChatSession _chat;
  final Content _message;
  final AiCall _call;
  final Duration? _timeout;
  late final StreamController<GenerateContentResponse> _controller;
  final List<GenerateContentResponse> _chunks = <GenerateContentResponse>[];
  StreamSubscription<GenerateContentResponse>? _inner;
  _Slot? _slot;
  bool _cancelled = false;

  Stream<GenerateContentResponse> get stream => _controller.stream;

  Future<void> _onListen() async {
    final _Slot slot = _chat._takeSlot();
    _slot = slot;
    try {
      await _chat._waitForTurn(slot, _call);
    } on Object catch (error) {
      _fail(error);
      return;
    }
    if (_cancelled) {
      _call.dispose();
      slot.release();
      return;
    }
    final List<Content> contents = <Content>[..._chat._history, _message];
    final Stream<GenerateContentResponse> source;
    try {
      final StreamRequest request = _chat._core.streamRequest(
        contents,
        _chat._settings,
      );
      source = _chat._core.generateStream(request, _call, _timeout);
    } on Object catch (error) {
      _call.dispose();
      _fail(error);
      return;
    }
    final StreamSubscription<GenerateContentResponse> inner = source.listen(
      _onChunk,
      onError: _onError,
      onDone: _onDone,
    );
    _inner = inner;
    if (_controller.isPaused) {
      inner.pause();
    }
  }

  void _onChunk(GenerateContentResponse chunk) {
    _chunks.add(chunk);
    _controller.add(chunk);
  }

  void _onError(Object error, StackTrace stackTrace) {
    _inner?.cancel().ignore();
    _fail(error, stackTrace);
  }

  void _onDone() {
    if (_chunks.isNotEmpty) {
      _chat._appendTurn(_message, aggregateResponses(_chunks));
    }
    _slot?.release();
    unawaited(_controller.close());
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    _slot?.release();
    if (_cancelled) {
      return;
    }
    _controller.addError(error, stackTrace);
    unawaited(_controller.close());
  }

  Future<void> _onCancel() async {
    _cancelled = true;
    final StreamSubscription<GenerateContentResponse>? inner = _inner;
    _inner = null;
    try {
      await inner?.cancel();
    } finally {
      _slot?.release();
    }
  }
}
