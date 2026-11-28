// A chat: two messages, the second one streamed. The session keeps the history
// and sends all of it with each message, so the cost of a turn grows with the
// length of the conversation.
//
//     dart run example/chat.dart --api-key <key> --app-id <id> \
//         --project-id <project> --model <model>

import 'dart:io';

import 'package:firebase_ai_dart/firebase_ai_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final ExampleSetup setup = exampleSetup(arguments);
  try {
    final GenerativeModel model = setup.generativeModel(
      systemInstruction: Content.system('You are a concise assistant.'),
    );
    final ChatSession chat = model.startChat();

    final GenerateContentResponse first = await chat.sendMessage(
      Content.text('My favourite number is 42. Say hello.'),
    );
    print('model: ${first.text}');

    stdout.write('model: ');
    await for (final GenerateContentResponse chunk in chat.sendMessageStream(
      Content.text('What is my favourite number?'),
    )) {
      stdout.write(chunk.text ?? '');
    }
    stdout.writeln();

    // Two entries per successful turn: the message and the reply. A turn whose
    // reply was blocked or empty leaves the history unchanged.
    print('history: ${chat.history.length} entries');
  } on FirebaseAIException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await setup.close();
  }
}
