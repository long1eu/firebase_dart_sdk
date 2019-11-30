// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

import 'package:firebase_internal/firebase_internal.dart';
import 'package:hive/hive.dart';

/// This class should hold object that the Firebase services depend upon and platform specific.
abstract class PlatformDependencies {
  const PlatformDependencies();

  AuthUrlPresenter get authUrlPresenter;

  Stream<bool> get isBackgroundChanged;

  Box<dynamic> get box;

  HeaderBuilder get headersBuilder;

  String get locale;

  InternalTokenProvider get authProvider;

  Future<bool> get isNetworkConnected;

  bool get isBackground;
}

/// Signature used to retrieved platform specific headers for every request made by Firebase services.
typedef HeaderBuilder = Map<String, String> Function();

/// Signature used to receiving the locale for requests made by Firebase services that provides a way to change the
/// locale of the action.
typedef CurrentLocale = String Function();
