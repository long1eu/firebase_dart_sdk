// File created by
// Lung Razvan <long1eu>
// on 31/08/2020

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

class GenerateFirebaseOptions extends Command<void> {
  GenerateFirebaseOptions() {
    argParser
      ..addMultiOption(
        'package',
        help: 'Generated FirebaseOptions for the package you are using.',
        defaultsTo: <String>['dart'],
        allowed: <String>['vm', 'dart'],
        allowedHelp: <String, String>{
          'vm': 'This will build the FirebaseOptions that can be used for the `firebase_core_vm` package.',
          'dart': 'This will build the FirebaseOptions that can be used for the `firebase_core_dart` package.',
        },
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'The google_services.yaml file used to generate the FirebaseOptions.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Directory to save the generated files to.',
      );
  }

  @override
  String get name => 'generate:options';

  @override
  String get description => 'Generates firebase options for different platforms base on the $configDefaultName';

  String get configDefaultName => 'google_services.yaml';

  File get _config {
    final String config = argResults['config'];
    if (config == null || config.isEmpty) {
      final File configFile = File(join(Directory.current.path, configDefaultName));
      if (configFile.existsSync()) {
        return configFile;
      } else {
        stderr.writeln(
            'Config file is not specified and the ${configFile.path} was not found. Ether add the file at ${configFile.path} or specify the path using `--config` option.');
        exit(1);
      }
    } else {
      final File configFile = File(config).absolute;
      if (configFile.existsSync()) {
        return configFile;
      } else {
        stderr.writeln(
            'Config file was not found at ${configFile.path}. Ether add the file at ${join(Directory.current.path, configDefaultName)} or specify the path using `--config` option.');
        exit(1);
      }
    }
  }

  Directory get _output {
    final String output = argResults['output'];
    Directory outputFile;
    if (output == null || output.isEmpty) {
      outputFile = Directory(join(Directory.current.path, 'lib', 'generated'));
      if (!outputFile.existsSync()) {
        outputFile.createSync(recursive: true);
      }
    } else {
      outputFile = Directory(output).absolute;
      if (!outputFile.existsSync()) {
        outputFile.createSync(recursive: true);
      }
    }

    return outputFile;
  }

  void _addVmPlatform(StringBuffer buffer, String os, Map<String, dynamic> data) {
    for (String key in <String>[
      'api_key',
      'project_number',
      'project_id',
      if (os == 'android' || os == 'ios' || os == 'web') 'app_id',
    ]) {
      if (!data.containsKey(key)) {
        stderr.writeln(
            'The config file you specified doesn\'t contain a valid $key for $os. You can get this value from here https://console.cloud.google.com/projectselector2/home/dashboard.');
        exit(1);
      }
    }

    final String projectNumber = data['project_number'].toString();
    final String appId = data['app_id'] ?? _generateAppId(projectNumber, os);

    if (os == 'web') {
      buffer.writeln('if (kIsWeb) {');
    } else {
      buffer.writeln("if (!kIsWeb && Platform.operatingSystem == '$os') {");
    }

    buffer //
      ..writeln('    return const FirebaseOptions(')
      ..writeln("      apiKey: '${data['api_key']}',")
      ..writeln("      appId: '$appId',")
      ..writeln("      messagingSenderId: '$projectNumber',")
      ..writeln("      projectId: '${data['project_id']}',");

    if (data.containsKey('database_url')) {
      buffer.writeln("      databaseUrl: '${data['database_url']}',");
    }
    if (data.containsKey('ga_tracking_id')) {
      buffer.writeln("      gaTrackingId: '${data['ga_tracking_id']}',");
    }
    if (data.containsKey('storage_bucket')) {
      buffer.writeln("      storageBucket: '${data['storage_bucket']}',");
    }
    if (data.containsKey('auth_domain')) {
      buffer.writeln("      authDomain: '${data['auth_domain']}',");
    }
    if (data.containsKey('measurement_id')) {
      buffer.writeln("      measurementId: '${data['measurement_id']}',");
    }
    if (data.containsKey('tracking_id')) {
      buffer.writeln("      trackingId: '${data['tracking_id']}',");
    }
    if (data.containsKey('client_id')) {
      buffer.writeln("      clientId: '${data['client_id']}',");
    }
    if (data.containsKey('data_collection_enabled')) {
      buffer.writeln('      dataCollectionEnabled: ${data['data_collection_enabled']},');
    }

    buffer //
      ..writeln('    );')
      ..write('  } else ');
  }

  void _addDartPlatform(StringBuffer buffer, String os, Map<String, dynamic> data) {
    for (String key in <String>[
      'api_key',
      'project_number',
      'project_id',
      if (os == 'android' || os == 'ios' || os == 'web') 'app_id',
    ]) {
      if (!data.containsKey(key)) {
        stderr.writeln(
            'The config file you specified doesn\'t contain a valid $key for $os. You can get this value from here https://console.cloud.google.com/projectselector2/home/dashboard.');
        exit(1);
      }
    }

    final String projectNumber = data['project_number'].toString();
    final String appId = data['app_id'] ?? _generateAppId(projectNumber, os);

    if (os == 'web') {
      buffer.writeln('if (kIsWeb) {');
    } else {
      buffer.writeln("if (!kIsWeb && Platform.operatingSystem == '$os') {");
    }

    buffer //
      ..writeln('    return const FirebaseOptions(')
      ..writeln("      apiKey: '${data['api_key']}',")
      ..writeln("      appId: '$appId',")
      ..writeln("      messagingSenderId: '$projectNumber',")
      ..writeln("      projectId: '${data['project_id']}',");

    if (data.containsKey('database_url')) {
      buffer.writeln("      databaseURL: '${data['database_url']}',");
    }
    if (data.containsKey('storage_bucket')) {
      buffer.writeln("      storageBucket: '${data['storage_bucket']}',");
    }
    if (data.containsKey('auth_domain')) {
      buffer.writeln("      authDomain: '${data['auth_domain']}',");
    }
    if (data.containsKey('measurement_id')) {
      buffer.writeln("      measurementId: '${data['measurement_id']}',");
    }
    if (os == 'ios') {
      if (data.containsKey('tracking_id')) {
        buffer.writeln("      trackingID: '${data['tracking_id']}',");
      }
      if (data.containsKey('deep_link_url_scheme')) {
        buffer.writeln("      deepLinkURLScheme: '${data['deep_link_url_scheme']}',");
      }
      if (data.containsKey('android_client_id')) {
        buffer.writeln("      androidClientId: '${data['android_client_id']}',");
      }
      if (data.containsKey('ios_client_id')) {
        buffer.writeln("      iosClientId: '${data['ios_client_id']}',");
      }
      if (data.containsKey('ios_bundle_id')) {
        buffer.writeln("      iosBundleId: '${data['ios_bundle_id']}',");
      }
      if (data.containsKey('app_group_id')) {
        buffer.writeln("      appGroupId: '${data['app_group_id']}',");
      }
    }

    buffer //
      ..writeln('    );')
      ..write('  } else ');
  }

  String _generateAppId(String projectNumber, String os) {
    assert(os != 'android' || os != 'ios' || os != 'web');

    final String prefix = '1:$projectNumber:$os';
    final List<int> bytes = utf8.encode(prefix);
    final Digest hash = sha1.convert(bytes);

    return '$prefix:$hash';
  }

  @override
  Future<void> run() async {
    final File config = _config;
    final Directory output = _output;

    final List<String> package = List<String>.from(argResults['package']);
    if (package.isEmpty) {
      stdout.writeln('Nothing to build. No package specified.');
      return;
    }

    final YamlMap data = loadYaml(config.readAsStringSync());
    final Map<String, dynamic> general = Map<String, dynamic>.from(data['general'] ?? <String, String>{});

    for (String package in package) {
      final StringBuffer buffer = StringBuffer(package == 'dart' ? _headerDart : _headerVm);
      for (String os in data.keys) {
        if (os == 'general') {
          continue;
        }
        if (package == 'dart') {
          _addDartPlatform(buffer, os, <String, dynamic>{...general, ...data[os]});
        } else {
          _addVmPlatform(buffer, os, <String, dynamic>{...general, ...data[os]});
        }
      }

      buffer //
        ..writeln('{')
        ..writeln("    throw UnsupportedError('\${Platform.operatingSystem} not supported.');")
        ..writeln('  }')
        ..writeln('}')
        ..writeln();

      File(join(output.path, 'firebase_options_$package.dart')).writeAsStringSync(buffer.toString());
    }
  }
}

const String _headerVm = '''// GENERATED_FILE: DO NOT EDIT

import 'dart:io';

import 'package:firebase_core_vm/firebase_core_vm.dart';

FirebaseOptions get firebaseOptions {
  ''';

const String _headerDart = '''// GENERATED_FILE: DO NOT EDIT

import 'dart:io';

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart' show kIsWeb;

FirebaseOptions get firebaseOptions {
  ''';
