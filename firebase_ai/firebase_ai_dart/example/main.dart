// Asks a Gemini model one question through Firebase AI Logic and prints the
// answer.
//
// There is no emulator for AI Logic; pass your own project. The call is billed
// to it:
//
//     dart run example/main.dart <api key> <app id> <project id> <model name>

import 'dart:io';

import 'package:firebase_ai_dart/firebase_ai_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: dart run example/main.dart '
      '<api key> <app id> <project id> <model name>',
    );
    exit(64);
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: arguments[0],
      appId: arguments[1],
      projectId: arguments[2],
    ),
  );
  final FirebaseAI ai = FirebaseAI.googleAI(app: app);
  try {
    final GenerativeModel model = ai.generativeModel(model: arguments[3]);
    final GenerateContentResponse response = await model.generateContent(
      <Content>[Content.text('Write a haiku about Dart.')],
    );
    print(response.text);
  } on FirebaseAIException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await ai.close();
    await app.delete();
  }
}
