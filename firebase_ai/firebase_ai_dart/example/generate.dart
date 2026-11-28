// One answer: a system instruction, a generation configuration, the usage
// numbers, the finish reason, and a token count of the prompt.
//
//     dart run example/generate.dart --api-key <key> --app-id <id> \
//         --project-id <project> --model <model> ["your prompt"]

import 'package:firebase_ai_dart/firebase_ai_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final ExampleSetup setup = exampleSetup(arguments);
  try {
    final GenerativeModel model = setup.generativeModel(
      systemInstruction: Content.system('Answer in one short paragraph.'),
      generationConfig: const GenerationConfig(
        temperature: 0.4,
        maxOutputTokens: 400,
      ),
    );
    final List<Content> prompt = <Content>[
      Content.text(
        setup.prompt.isEmpty ? 'Why is the sky blue?' : setup.prompt,
      ),
    ];
    final GenerateContentResponse response = await model.generateContent(
      prompt,
    );
    // `text` throws a FirebaseAIException with the code response-error when the
    // prompt or the answer was blocked; the finish reason says why an answer
    // ended.
    print(response.text);
    final FinishReason? reason = response.candidates.first.finishReason;
    final UsageMetadata? usage = response.usageMetadata;
    print('finish reason: ${reason?.name}');
    print(
      'tokens: prompt ${usage?.promptTokenCount}, '
      'answer ${usage?.candidatesTokenCount}, total ${usage?.totalTokenCount}',
    );
    final CountTokensResponse count = await model.countTokens(prompt);
    print('countTokens of the prompt: ${count.totalTokens}');
  } on FirebaseAIException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await setup.close();
  }
}
