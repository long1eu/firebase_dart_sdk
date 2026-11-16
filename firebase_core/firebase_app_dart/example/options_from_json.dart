// FirebaseOptions from a JSON file or a map, and back.
//
//     dart run example/options_from_json.dart [path/to/options.json]
//
// Needs nothing else: no emulator, no network. Without an argument the
// program reads the JSON below. The keys are those of FirebaseOptions.toJson
// (the names of the Android resource values), not those of
// google-services.json or of the web config object; the last part of this
// program maps a web config object.

import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';

const String _sample = '''
{
  "google_api_key": "<YOUR_API_KEY>",
  "google_app_id": "1:1234567890:dart:example",
  "project_id": "my-project",
  "google_storage_bucket": "my-project.appspot.com"
}
''';

void main(List<String> arguments) {
  final String source = arguments.isEmpty
      ? _sample
      : File(arguments.single).readAsStringSync();

  // 1. From the JSON of FirebaseOptions.toJson.
  final FirebaseOptions options = FirebaseOptions.fromJson(
    jsonDecode(source) as Map<String, dynamic>,
  );
  print('project: ${options.projectId}');
  print('bucket: ${options.storageBucket}');

  final FirebaseApp app = FirebaseApp.withOptions(options);
  print('app created for ${app.options.projectId}');

  // 2. Back to JSON, for a file of your own. Unset values are null.
  final Map<String, String?> json = options.toJson();
  print('round trip equal: ${FirebaseOptions.fromJson(json) == options}');

  // 3. A missing required key throws an ArgumentError.
  try {
    FirebaseOptions.fromJson(<String, dynamic>{'project_id': 'my-project'});
  } on ArgumentError catch (e) {
    print('missing keys: ${e.message}');
  }

  // 4. The config object of a web app in the Firebase console has other key
  // names: map them yourself.
  const Map<String, String> webConfig = <String, String>{
    'apiKey': '<YOUR_API_KEY>',
    'appId': '1:1234567890:web:0123456789abcdef',
    'projectId': 'my-project',
    'storageBucket': 'my-project.appspot.com',
    'messagingSenderId': '1234567890',
  };
  final FirebaseOptions fromWeb = FirebaseOptions(
    apiKey: webConfig['apiKey']!,
    appId: webConfig['appId']!,
    projectId: webConfig['projectId'],
    storageBucket: webConfig['storageBucket'],
    messagingSenderId: webConfig['messagingSenderId'],
  );
  print('from a web config: ${fromWeb.projectId}');
}
