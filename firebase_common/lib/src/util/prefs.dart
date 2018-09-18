// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_common/src/annotations.dart';

@keepForSdk
class Prefs {
  final File file;
  Completer<void> completer = Completer();
  Map<String, dynamic> json;

  Prefs(this.file) {
    final String data = file.readAsStringSync();
    json = (jsonDecode(data) as Map<dynamic, dynamic>).cast<String, dynamic>();
  }

  bool contains(String key) => json.containsKey(key);

  void setBool(String key, bool value) {
    json[key] = value;
    file.openSync();
    _complete();
  }

  bool getBool(String key) => json[key];

  void _complete() {
    if (completer.isCompleted) {
      _write();
    } else {
      completer.future.then((_) => _write());
    }
  }

  Future<void> _write() {
    return file.writeAsString(jsonEncode(json)).then((_) {
      completer.complete();
      completer = Completer();
    });
  }
}
