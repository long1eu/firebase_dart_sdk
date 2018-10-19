// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_common/src/internal/shared_preferences.dart';
import 'package:test/test.dart';

// ignore_for_file: avoid_as
void main() {
  final String path = '${Directory.current.path}/build/prefs.json';
  const Map<String, dynamic> kTestValues = <String, dynamic>{
    'flutter.String': 'hello world',
    'flutter.bool': true,
    'flutter.int': 42,
    'flutter.double': 3.14159,
    'flutter.List': <String>['foo', 'bar'],
  };

  const Map<String, dynamic> kTestValues2 = <String, dynamic>{
    'flutter.String': 'goodbye world',
    'flutter.bool': false,
    'flutter.int': 1337,
    'flutter.double': 2.71828,
    'flutter.List': <String>['baz', 'quox'],
  };

  const String testContents =
      '''{"String": "hello world", "bool": true, "int": 42, "double": 3.14159, "List": ["foo", "bar"]}''';

  test('reading', () async {
    await File(path).writeAsString(testContents);

    final SharedPreferences preferences =
        await SharedPreferences.getInstance(path);

    expect(preferences.getString('String'), kTestValues['flutter.String']);
    expect(preferences.getBool('bool'), kTestValues['flutter.bool']);
    expect(preferences.getInt('int'), kTestValues['flutter.int']);
    expect(preferences.getDouble('double'), kTestValues['flutter.double']);
    expect(preferences.getStringList('List'), kTestValues['flutter.List']);
  });

  test('writing', () async {
    File(path).deleteSync();
    final SharedPreferences preferences =
        await SharedPreferences.getInstance(path);

    final List<String> values = <String>[];
    preferences.onChange.listen(values.add);

    final Editor editor = preferences.edit()
      ..putString('String', kTestValues2['flutter.String'] as String)
      ..putBool('bool', kTestValues2['flutter.bool'] as bool)
      ..putInt('int', kTestValues2['flutter.int'] as int)
      ..putDouble('double', kTestValues2['flutter.double'] as double)
      ..putStringList('List', kTestValues2['flutter.List'] as List<String>);

    await editor.commit();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    expect(values,
        containsAll(<String>['String', 'bool', 'int', 'double', 'List']));

    expect(preferences.getString('String'), kTestValues2['flutter.String']);
    expect(preferences.getBool('bool'), kTestValues2['flutter.bool']);
    expect(preferences.getInt('int'), kTestValues2['flutter.int']);
    expect(preferences.getDouble('double'), kTestValues2['flutter.double']);
    expect(preferences.getStringList('List'), kTestValues2['flutter.List']);
  });

  test('removing', () async {
    File(path)
      ..deleteSync()
      ..writeAsStringSync(testContents);

    final SharedPreferences preferences =
        await SharedPreferences.getInstance(path);

    const String key = 'testKey';
    preferences.edit()
      ..putString(key, null)
      ..putBool(key, null)
      ..putInt(key, null)
      ..putDouble(key, null)
      ..putStringList(key, null)
      ..apply();

    await Future<void>.delayed(const Duration(seconds: 1));

    expect(preferences.all, hasLength(5));
    expect(preferences.all, jsonDecode(testContents));

    preferences.edit()
      ..putString('String', null)
      ..apply();
    expect(preferences.all, hasLength(4));

    preferences.edit()
      ..remove('bool')
      ..apply();
    expect(preferences.all, hasLength(3));
  });

  test('clearing', () async {
    await File(path).writeAsString(testContents);
    final SharedPreferences preferences =
        await SharedPreferences.getInstance(path);

    await (preferences.edit()..clear()).commit();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    expect(preferences.getString('String'), null);
    expect(preferences.getBool('bool'), null);
    expect(preferences.getInt('int'), null);
    expect(preferences.getDouble('double'), null);
    expect(preferences.getStringList('List'), null);
  });
}
