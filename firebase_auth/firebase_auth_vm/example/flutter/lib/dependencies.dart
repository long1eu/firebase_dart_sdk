// File created by
// Lung Razvan <long1eu>
// on 29/02/2020

import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class Dependencies extends PlatformDependencies {
  Dependencies({@required this.box}) : headersBuilder = null;

  @override
  final Box<dynamic> box;

  @override
  final HeaderBuilder headersBuilder;

  @override
  InternalTokenProvider get authProvider => null;

  @override
  AuthUrlPresenter get authUrlPresenter => null;

  @override
  bool get isBackground => false;

  @override
  Future<bool> get isNetworkConnected => Future<bool>.value(true);

  @override
  String get locale => 'en';

  @override
  Stream<bool> get isBackgroundChanged => Stream<bool>.fromIterable(<bool>[false]);
}
