// Two ways to end a call early: a `timeout` that replaces the model's
// `requestTimeout` for one call, and an `abortTrigger` that ends it when a
// future completes. An abort stops this program's work only; the service may
// still finish the request and bill it.
//
//     dart run example/cancel.dart --api-key <key> --app-id <id> \
//         --project-id <project> --model <model>

import 'dart:async';
import 'dart:io';

import 'package:firebase_ai_dart/firebase_ai_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final ExampleSetup setup = exampleSetup(arguments);
  try {
    final GenerativeModel model = setup.generativeModel();
    final List<Content> prompt = <Content>[
      Content.text('Write a long essay about the history of the telegraph.'),
    ];

    // 1. A deadline: the call fails with deadline-exceeded when it runs out.
    try {
      await model.generateContent(
        prompt,
        timeout: const Duration(milliseconds: 50),
      );
    } on FirebaseAIException catch (e) {
      print('timeout: ${e.code}, local failure: ${e.httpStatus == null}');
    }

    // 2. An abort trigger: stop a stream after the first chunk.
    final Completer<void> stop = Completer<void>();
    try {
      await for (final GenerateContentResponse chunk
          in model.generateContentStream(prompt, abortTrigger: stop.future)) {
        stdout.write(chunk.text ?? '');
        if (!stop.isCompleted) {
          stop.complete();
        }
      }
    } on FirebaseAIException catch (e) {
      print('\nabortTrigger: ${e.code}');
    }
  } finally {
    await setup.close();
  }
}
