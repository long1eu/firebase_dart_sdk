// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:async';

import 'package:sqflite/sqflite.dart';

typedef void Runnable();
typedef Future<T> Supplier<T>();
typedef void Consumer<T>(T);
typedef Transaction<T> = FutureOr<T> Function([DatabaseExecutor transaction]);
