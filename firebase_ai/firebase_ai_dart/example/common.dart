// Setup shared by the examples in this directory: a FirebaseApp built from the
// command line and a FirebaseAI on top.
//
// There is no emulator for AI Logic: the examples talk to the project you name,
// and every call is billed to it. Run any of them with
//
//     dart run example/<name>.dart --api-key <key> --app-id <id> \
//         --project-id <project> --model <model name> [--backend agent-platform] \
//         [--location <location>] [prompt]
//
// The prompt is whatever follows the options. Without App Check enforcement in
// the project, the calls need no token; with it, give the FirebaseApp an App
// Check provider (see the README).

import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_ai_dart/firebase_ai_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

/// The app, the [FirebaseAI] and the model name an example runs with.
class ExampleSetup {
  ExampleSetup._(this.app, this.ai, this.model, this.prompt);

  /// The app built from `--api-key`, `--app-id` and `--project-id`.
  final FirebaseApp app;

  /// The instance for `--backend` (and `--location`).
  final FirebaseAI ai;

  /// The value of `--model`.
  final String model;

  /// The arguments that follow the options, joined with spaces; empty when
  /// there are none.
  final String prompt;

  /// A model of [ai] named `--model`.
  GenerativeModel generativeModel({
    GenerationConfig? generationConfig,
    List<Tool>? tools,
    ToolConfig? toolConfig,
    Content? systemInstruction,
  }) => ai.generativeModel(
    model: model,
    generationConfig: generationConfig,
    tools: tools,
    toolConfig: toolConfig,
    systemInstruction: systemInstruction,
  );

  /// Closes [ai] and deletes [app].
  Future<void> close() async {
    await ai.close();
    await app.delete();
  }
}

/// Reads the options of [arguments]. The program stops with a usage message
/// when `--api-key`, `--app-id`, `--project-id` or `--model` is missing, or
/// `--backend` is not `google-ai` or `agent-platform`.
ExampleSetup exampleSetup(List<String> arguments) {
  final ArgParser parser = ArgParser()
    ..addOption('api-key', help: 'The API key of the project.')
    ..addOption('app-id', help: 'The app id, for example 1:123:web:abc.')
    ..addOption('project-id', help: 'The project id.')
    ..addOption('model', help: 'The model name. There is no default.')
    ..addOption(
      'backend',
      allowed: <String>['google-ai', 'agent-platform'],
      defaultsTo: 'google-ai',
      help: 'The backend.',
    )
    ..addOption(
      'location',
      defaultsTo: 'global',
      help: 'The location; used only with agent-platform.',
    );
  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    _usage(parser, error.message);
  }
  final String? apiKey = results.option('api-key');
  final String? appId = results.option('app-id');
  final String? projectId = results.option('project-id');
  final String? model = results.option('model');
  if (apiKey == null || appId == null || projectId == null || model == null) {
    _usage(
      parser,
      'The options --api-key, --app-id, --project-id and --model are required.',
    );
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(apiKey: apiKey, appId: appId, projectId: projectId),
  );
  void logger(AILogLevel level, String message) =>
      stderr.writeln('[${level.name}] $message');
  final FirebaseAI ai = results.option('backend') == 'agent-platform'
      ? FirebaseAI.agentPlatform(
          app: app,
          location: results.option('location') ?? 'global',
          logger: logger,
        )
      : FirebaseAI.googleAI(app: app, logger: logger);
  return ExampleSetup._(app, ai, model, results.rest.join(' '));
}

Never _usage(ArgParser parser, String problem) {
  stderr
    ..writeln(problem)
    ..writeln('Usage: dart run example/<name>.dart [options] [prompt]')
    ..writeln(parser.usage);
  exit(64);
}
