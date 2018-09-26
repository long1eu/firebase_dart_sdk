// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:sqflite/sqflite.dart';

typedef void Runnable();
typedef Future<T> Supplier<T>();
typedef void Consumer<T>(T value);
typedef Transaction<T> = Future<T> Function(DatabaseExecutor transaction);

/// Will be called with the new value or the error if an error occurred. It's
/// guaranteed that exactly one of value or error will be non-null.
///
/// The [value] of the event. null if there was an error.
/// The [error] if there was error. null otherwise.
typedef EventListener<T> = void Function(T value, FirebaseFirestoreError error);
