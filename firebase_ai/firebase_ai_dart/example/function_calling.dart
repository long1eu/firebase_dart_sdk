// Manual function calling: the model asks for a function, the program runs it
// and sends the result back in the same chat.
//
//     dart run example/function_calling.dart --api-key <key> --app-id <id> \
//         --project-id <project> --model <model>

import 'package:firebase_ai_dart/firebase_ai_dart.dart';

import 'common.dart';

/// The function the model may call. Here it answers from a fixed table.
Map<String, Object?> _currentWeather(Map<String, Object?> args) {
  final String city = '${args['city']}';
  return <String, Object?>{
    'city': city,
    'temperature_celsius': 18,
    'sky': 'clear',
  };
}

Future<void> main(List<String> arguments) async {
  final ExampleSetup setup = exampleSetup(arguments);
  try {
    final GenerativeModel model = setup.generativeModel(
      tools: <Tool>[
        Tool.functionDeclarations(<FunctionDeclaration>[
          FunctionDeclaration(
            'current_weather',
            'The current weather in a city.',
            parameters: Schema.object(
              properties: <String, Schema>{
                'city': Schema.string(description: 'The name of the city.'),
              },
            ),
          ),
        ]),
      ],
    );
    final ChatSession chat = model.startChat();
    GenerateContentResponse response = await chat.sendMessage(
      Content.text(
        setup.prompt.isEmpty
            ? 'What is the weather in Cluj-Napoca?'
            : setup.prompt,
      ),
    );
    // A model may ask for several functions in a row; stop after a few rounds.
    for (int round = 0; round < 4; round++) {
      final List<FunctionCall> calls = response.functionCalls;
      if (calls.isEmpty) {
        break;
      }
      final List<FunctionResponse> results = <FunctionResponse>[
        for (final FunctionCall call in calls)
          FunctionResponse(call.name, _currentWeather(call.args), id: call.id),
      ];
      response = await chat.sendMessage(Content.functionResponses(results));
    }
    print(response.text);
  } on FirebaseAIException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await setup.close();
  }
}
