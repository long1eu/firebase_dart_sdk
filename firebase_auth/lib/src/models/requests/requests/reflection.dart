// File created by
// Lung Razvan <long1eu>
// on 06/12/2019

import 'dart:mirrors';

import 'index.dart';

// ignore_for_file: unused_import
void main() {
  final LibraryMirror requests = currentMirrorSystem().findLibrary(const Symbol('requests'));

  final List<String> classes = requests.declarations.values
      .whereType<ClassMirror>()
      .where((ClassMirror it) => !it.isPrivate && it.isAbstract)
      .map((ClassMirror it) =>
          it.simpleName.toString().replaceAllMapped(RegExp('Symbol\\("(.+?)"\\)'), (Match match) => match.group(1)))
      .toList()
        ..sort();

  print(classes);
}
