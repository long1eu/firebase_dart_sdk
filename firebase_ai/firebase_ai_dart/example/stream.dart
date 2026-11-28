// A streamed answer: each chunk is printed as it arrives. The last chunk has
// the finish reason and the usage numbers.
//
//     dart run example/stream.dart --api-key <key> --app-id <id> \
//         --project-id <project> --model <model> ["your prompt"]

import 'dart:io';

import 'package:firebase_ai_dart/firebase_ai_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final ExampleSetup setup = exampleSetup(arguments);
  try {
    final GenerativeModel model = setup.generativeModel();
    final Stream<GenerateContentResponse> chunks = model
        .generateContentStream(<Content>[
          Content.text(
            setup.prompt.isEmpty ? 'Tell me a short story.' : setup.prompt,
          ),
        ]);
    int count = 0;
    UsageMetadata? usage;
    await for (final GenerateContentResponse chunk in chunks) {
      count++;
      stdout.write(chunk.text ?? '');
      usage = chunk.usageMetadata ?? usage;
    }
    stdout.writeln();
    print('$count chunks, ${usage?.totalTokenCount} tokens');
  } on FirebaseAIException catch (e) {
    // A stream that fails after some chunks keeps what arrived in `response`.
    print('\nFailed: ${e.code}: ${e.message}');
  } finally {
    await setup.close();
  }
}
