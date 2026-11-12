// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:async';

typedef Runnable = void Function();
typedef Supplier<T> = Future<T> Function();
typedef Consumer<T> = void Function(T value);
typedef Transaction<T> = Future<T> Function();
