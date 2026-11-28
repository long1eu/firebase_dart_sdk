// Structured output: the answer is JSON that follows a schema.
//
//     dart run example/structured_output.dart --api-key <key> --app-id <id> \
//         --project-id <project> --model <model>

import 'dart:convert';

import 'package:firebase_ai_dart/firebase_ai_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final ExampleSetup setup = exampleSetup(arguments);
  try {
    final GenerativeModel model = setup.generativeModel(
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: Schema.array(
          items: Schema.object(
            properties: <String, Schema>{
              'name': Schema.string(),
              'minutes': Schema.integer(description: 'Preparation time.'),
              'vegetarian': Schema.boolean(),
            },
            optionalProperties: const <String>['vegetarian'],
          ),
        ),
      ),
    );
    final GenerateContentResponse response = await model.generateContent(
      <Content>[Content.text('Give me three quick dinner ideas.')],
    );
    // The schema shapes the answer; the program still checks what it decodes.
    final Object? decoded = jsonDecode(response.text ?? 'null');
    if (decoded is! List<Object?>) {
      print('Unexpected answer: ${response.text}');
      return;
    }
    for (final Object? item in decoded) {
      print(item);
    }
  } on FirebaseAIException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } on FormatException catch (e) {
    print('The answer is not JSON: ${e.message}');
  } finally {
    await setup.close();
  }
}
