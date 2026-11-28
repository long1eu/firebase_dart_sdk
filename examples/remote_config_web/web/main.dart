// The page: connect to a project with an API key, an app id and a project id, fetch and activate its
// Remote Config values, show them in a table with their source, and log the realtime updates.
import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/web.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:web/web.dart';

/// Values the page shows before a fetch, and for keys the template does not have.
const Map<String, Object> _defaults = <String, Object>{
  'welcome_message': 'Hello',
  'feature_enabled': false,
};

T _el<T extends Element>(String id) => document.getElementById(id) as T;

KeyValueStore? _store;
FirebaseInstallations? _installations;
FirebaseRemoteConfig? _config;
FirebaseApp? _app;
StreamSubscription<RemoteConfigUpdate>? _updates;
int _generation = 0;

void main() {
  _el<HTMLFormElement>('connect').onSubmit.listen((Event e) {
    e.preventDefault();
    unawaited(_connect());
  });
  _el<HTMLButtonElement>(
    'fetch',
  ).onClick.listen((_) => unawaited(_fetchAndActivate()));
}

Future<void> _disconnect() async {
  _generation++;
  await _updates?.cancel();
  _updates = null;
  final FirebaseRemoteConfig? config = _config;
  final FirebaseInstallations? installations = _installations;
  final KeyValueStore? store = _store;
  final FirebaseApp? app = _app;
  _config = null;
  _installations = null;
  _store = null;
  _app = null;
  try {
    await config?.close();
    await installations?.close();
    await store?.close();
    await app?.delete();
  } on Object catch (error) {
    _showError('Closing the previous connection failed: $error');
  }
}

Future<void> _connect() async {
  await _disconnect();
  _showError('');
  _el<HTMLElement>('log').textContent = '';
  _el<HTMLElement>('values').textContent = '';
  _setStatus('Connecting');
  final int generation = _generation;
  try {
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: _field('f-key'),
        appId: _field('f-app'),
        projectId: _field('f-project'),
      ),
      name: 'remote-config-web-$generation',
    );
    final KeyValueStore store = IndexedDbKeyValueStore();
    final FirebaseInstallations installations = FirebaseInstallations(
      app,
      store: store,
    );
    final FirebaseRemoteConfig config = FirebaseRemoteConfig(
      app,
      installations: installations,
      defaults: _defaults,
    );
    _app = app;
    _store = store;
    _installations = installations;
    _config = config;
    await config.ensureInitialized();
    if (generation != _generation) return;
    _listen(config, generation);
    _el<HTMLButtonElement>('fetch').disabled = false;
    _setStatus('Connected; nothing fetched yet');
    _showValues(config);
    _showInfo(config);
  } on Object catch (error) {
    _showError('Could not connect: $error');
    _setStatus('Not connected');
  }
}

String _field(String id) => _el<HTMLInputElement>(id).value.trim();

Future<void> _fetchAndActivate() async {
  final FirebaseRemoteConfig? config = _config;
  if (config == null) return;
  final int generation = _generation;
  final HTMLButtonElement button = _el('fetch');
  button.disabled = true;
  _showError('');
  _setStatus('Fetching');
  try {
    final bool activated = await config.fetchAndActivate();
    if (generation != _generation) return;
    _setStatus(
      activated ? 'Fetched and activated' : 'Fetched; nothing new to activate',
    );
  } on FirebaseRemoteConfigException catch (error) {
    if (generation != _generation) return;
    _showError('${error.code}: ${error.message}');
    _setStatus('The fetch failed');
  } finally {
    if (generation == _generation) {
      button.disabled = false;
      _showValues(config);
      _showInfo(config);
    }
  }
}

void _listen(FirebaseRemoteConfig config, int generation) {
  _updates = config.onConfigUpdated.listen(
    (RemoteConfigUpdate update) async {
      if (generation != _generation) return;
      final List<String> keys = update.updatedKeys.toList()..sort();
      _log('Updated: ${keys.join(', ')}');
      await config.activate();
      if (generation != _generation) return;
      _showValues(config);
      _showInfo(config);
    },
    onError: (Object error) {
      if (generation != _generation) return;
      final String text = error is FirebaseRemoteConfigException
          ? error.code
          : '$error';
      _log('Realtime problem: $text', problem: true);
    },
  );
}

void _showValues(FirebaseRemoteConfig config) {
  final HTMLElement body = _el('values');
  body.textContent = '';
  final List<MapEntry<String, RemoteConfigValue>> entries =
      config.getAll().entries.toList()..sort(
        (
          MapEntry<String, RemoteConfigValue> a,
          MapEntry<String, RemoteConfigValue> b,
        ) => a.key.compareTo(b.key),
      );
  for (final MapEntry<String, RemoteConfigValue> entry in entries) {
    final HTMLTableRowElement row =
        document.createElement('tr') as HTMLTableRowElement;
    final HTMLTableCellElement source =
        document.createElement('td') as HTMLTableCellElement
          ..className = 'source-${entry.value.source.name}'
          ..textContent = entry.value.source.name;
    row
      ..append(_cell(entry.key))
      ..append(_cell(entry.value.asString()))
      ..append(source);
    body.append(row);
  }
}

HTMLTableCellElement _cell(String text) =>
    (document.createElement('td') as HTMLTableCellElement)..textContent = text;

void _showInfo(FirebaseRemoteConfig config) {
  final RemoteConfigInfo info = config.info;
  final DateTime? time = info.lastSuccessfulFetchTime;
  _el<HTMLElement>('last-fetch').textContent =
      '${info.lastFetchStatus.name}${time == null ? '' : ' at ${time.toLocal()}'}';
  _el<HTMLElement>('template').textContent =
      'fetched ${info.fetchedTemplateVersion ?? 'none'}, active ${info.activeTemplateVersion ?? 'none'}';
}

void _log(String message, {bool problem = false}) {
  final HTMLLIElement item = document.createElement('li') as HTMLLIElement
    ..className = problem ? 'problem' : ''
    ..textContent = '${DateTime.now().toLocal().toIso8601String()}  $message';
  _el<HTMLElement>('log').prepend(item);
}

void _setStatus(String text) => _el<HTMLElement>('status').textContent = text;

void _showError(String message) =>
    _el<HTMLElement>('error').textContent = message;
