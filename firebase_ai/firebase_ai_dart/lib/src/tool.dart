import 'dart:collection';

import 'package:firebase_ai_dart/src/schema.dart';
import 'package:meta/meta.dart';

/// How the model may call the declared functions.
enum FunctionCallingMode {
  /// The model decides whether to call a function (`AUTO`).
  auto('AUTO'),

  /// The model always calls a function (`ANY`).
  any('ANY'),

  /// The model never calls a function (`NONE`).
  none('NONE');

  const FunctionCallingMode(this._wire);

  final String _wire;

  /// The wire string.
  String toJson() => _wire;
}

enum _ToolKind {
  functionDeclarations('functionDeclarations'),
  googleSearch('googleSearch'),
  codeExecution('codeExecution'),
  urlContext('urlContext'),
  googleMaps('googleMaps');

  const _ToolKind(this.key);

  final String key;
}

/// Something the model can use while answering: functions the app runs, or a built-in tool.
@immutable
final class Tool {
  const Tool._(this._kind, [this._declarations]);

  final _ToolKind _kind;
  final List<FunctionDeclaration>? _declarations;

  /// Functions the model may ask the app to call.
  static Tool functionDeclarations(List<FunctionDeclaration> declarations) =>
      Tool._(
        _ToolKind.functionDeclarations,
        UnmodifiableListView<FunctionDeclaration>(
          List<FunctionDeclaration>.of(declarations),
        ),
      );

  /// Grounding with Google Search.
  static Tool googleSearch() => const Tool._(_ToolKind.googleSearch);

  /// Code the model writes and runs on the server.
  static Tool codeExecution() => const Tool._(_ToolKind.codeExecution);

  /// Reading the URLs given in the prompt.
  static Tool urlContext() => const Tool._(_ToolKind.urlContext);

  /// Grounding with Google Maps.
  static Tool googleMaps() => const Tool._(_ToolKind.googleMaps);

  /// The JSON object: one key naming the tool.
  Map<String, Object?> toJson() => <String, Object?>{
    _kind.key: switch (_declarations) {
      final List<FunctionDeclaration> declarations => <Object?>[
        for (final FunctionDeclaration declaration in declarations)
          declaration.toJson(),
      ],
      null => const <String, Object?>{},
    },
  };
}

/// A function the model may call.
@immutable
final class FunctionDeclaration {
  /// Declares [name], with [description] for the model and its [parameters] as an object schema.
  const FunctionDeclaration(this.name, this.description, {this.parameters});

  /// The name the model calls.
  final String name;

  /// What the function does; the model reads it.
  final String description;

  /// The parameters, as a [Schema.object].
  final Schema? parameters;

  /// The JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'description': description,
    'parameters': ?parameters?.toJson(),
  };
}

/// Options for the tools of a request.
@immutable
final class ToolConfig {
  /// Creates tool options.
  const ToolConfig({this.functionCallingConfig, this.retrievalConfig});

  /// How the model may call functions.
  final FunctionCallingConfig? functionCallingConfig;

  /// Context for the grounding tools.
  final RetrievalConfig? retrievalConfig;

  /// The `toolConfig` JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'functionCallingConfig': ?functionCallingConfig?.toJson(),
    'retrievalConfig': ?retrievalConfig?.toJson(),
  };
}

/// How the model may call the declared functions.
@immutable
final class FunctionCallingConfig {
  /// Creates function-calling options.
  const FunctionCallingConfig({this.mode, this.allowedFunctionNames});

  /// The mode.
  final FunctionCallingMode? mode;

  /// With [FunctionCallingMode.any], the functions the model may call.
  final List<String>? allowedFunctionNames;

  /// The `functionCallingConfig` JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': ?mode?.toJson(),
    'allowedFunctionNames': ?allowedFunctionNames,
  };
}

/// Context for the grounding tools: where the user is and their language.
@immutable
final class RetrievalConfig {
  /// Creates retrieval options.
  const RetrievalConfig({this.latLng, this.languageCode});

  /// The user's location.
  final LatLng? latLng;

  /// The user's language, for example `en-US`.
  final String? languageCode;

  /// The `retrievalConfig` JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'latLng': ?latLng?.toJson(),
    'languageCode': ?languageCode,
  };
}

/// A point on Earth, in degrees.
@immutable
final class LatLng {
  /// Creates a point. Both values must be finite when the request is made.
  const LatLng({required this.latitude, required this.longitude});

  /// The latitude.
  final double latitude;

  /// The longitude.
  final double longitude;

  /// The `latLng` JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'latitude': latitude,
    'longitude': longitude,
  };
}
