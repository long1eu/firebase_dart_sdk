// The page: connect to a project with an API key, an app id, a project id and a model,
// send a prompt and show the answer as it streams in. Stop aborts the request in the
// browser.
import 'dart:async';

import 'package:firebase_ai_dart/firebase_ai_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart';

T _el<T extends Element>(String id) => document.getElementById(id) as T;

FirebaseApp? _app;
FirebaseAI? _ai;
GenerativeModel? _model;
Completer<void>? _abort;
int _generation = 0;

void main() {
  _el<HTMLFormElement>('connect').onSubmit.listen((Event e) {
    e.preventDefault();
    unawaited(_connect());
  });
  _el<HTMLFormElement>('ask').onSubmit.listen((Event e) {
    e.preventDefault();
    unawaited(_send());
  });
  _el<HTMLButtonElement>('stop').onClick.listen((_) => _stop());
}

Future<void> _disconnect() async {
  _generation++;
  _stop();
  final FirebaseAI? ai = _ai;
  final FirebaseApp? app = _app;
  _ai = null;
  _app = null;
  _model = null;
  try {
    await ai?.close();
    await app?.delete();
  } on Object catch (error) {
    _showError('Closing the previous connection failed: $error');
  }
}

Future<void> _connect() async {
  await _disconnect();
  _showError('');
  _el<HTMLElement>('answer').textContent = '';
  _el<HTMLButtonElement>('send').disabled = true;
  final int generation = _generation;
  try {
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: _field('f-key'),
        appId: _field('f-app'),
        projectId: _field('f-project'),
      ),
      name: 'ai-web-$generation',
    );
    _app = app;
    final FirebaseAI ai =
        _el<HTMLSelectElement>('f-backend').value == 'agent-platform'
        ? FirebaseAI.agentPlatform(app: app, location: _field('f-location'))
        : FirebaseAI.googleAI(app: app);
    _ai = ai;
    _model = ai.generativeModel(model: _field('f-model'));
    _el<HTMLButtonElement>('send').disabled = false;
    _setStatus('Connected');
  } on Object catch (error) {
    _showError('Could not connect: $error');
    _setStatus('Not connected');
  }
}

String _field(String id) => _el<HTMLInputElement>(id).value.trim();

Future<void> _send() async {
  final GenerativeModel? model = _model;
  if (model == null) return;
  final int generation = _generation;
  final Completer<void> abort = Completer<void>();
  _abort = abort;
  final HTMLElement answer = _el('answer');
  answer.textContent = '';
  _showError('');
  _el<HTMLButtonElement>('send').disabled = true;
  _el<HTMLButtonElement>('stop').disabled = false;
  _setStatus('Waiting for the answer');
  try {
    final Stream<GenerateContentResponse> chunks = model.generateContentStream(
      <Content>[Content.text(_el<HTMLTextAreaElement>('f-prompt').value)],
      abortTrigger: abort.future,
    );
    await for (final GenerateContentResponse chunk in chunks) {
      if (generation != _generation) return;
      answer.textContent = '${answer.textContent}${chunk.text ?? ''}';
      _setStatus('Streaming');
    }
    _setStatus('Done');
  } on FirebaseAIException catch (error) {
    if (generation != _generation) return;
    if (error.code == 'cancelled') {
      _setStatus('Stopped');
    } else {
      _showError('${error.code}: ${error.message}');
      _setStatus('The request failed');
    }
  } finally {
    if (generation == _generation) {
      _abort = null;
      _el<HTMLButtonElement>('send').disabled = false;
      _el<HTMLButtonElement>('stop').disabled = true;
    }
  }
}

void _stop() {
  final Completer<void>? abort = _abort;
  if (abort != null && !abort.isCompleted) {
    abort.complete();
  }
}

void _setStatus(String text) => _el<HTMLElement>('status').textContent = text;

void _showError(String message) =>
    _el<HTMLElement>('error').textContent = message;
