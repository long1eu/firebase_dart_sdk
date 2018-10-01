// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:async';

typedef void Runnable();
typedef Future<T> Supplier<T>();
typedef void Consumer<T>(T value);
typedef Transaction<T> = Future<T> Function();
