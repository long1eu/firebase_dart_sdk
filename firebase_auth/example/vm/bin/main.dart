import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../lib/example.dart';

// ignore_for_file: avoid_relative_lib_imports
Future<void> main(List<String> arguments) async {
  await init();

  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    stdout
      ..writeln('Hi!')
      ..writeln('Welcome to Firebase Auth Dart SDK')
      ..writeln('What do you want to do?')
      ..writeln('')
      ..writeln('');


    /*
    languageCode
    currentUser
    fetchSignInMethodsForEmail
    signInWithEmailAndPassword
    signInWithEmailAndLink
    signInWithCredential
    signInAnonymously
    signInWithCustomToken
    createUserWithEmailAndPassword
    confirmPasswordReset
    checkActionCode
    verifyPasswordReset
    applyActionCode
    sendPasswordResetEmail
    sendSignInWithEmailLink
    signOut
    isSignInWithEmailLink
    verifyPhoneNumber
    * */
  } else {
    stdout //
      ..writeln('Hi ${getUserName(user)}!')
      ..writeln('Welcome back to Firebase Auth Dart SDK')
      ..writeln('What do you want to do?')
      ..writeln('')
      ..writeln('');
  }
}
