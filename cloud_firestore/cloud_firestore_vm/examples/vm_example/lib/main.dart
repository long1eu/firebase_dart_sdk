import 'dart:async';

import 'package:firebase_core/firebase_core_vm.dart';
import 'package:firebase_firestore/firebase_firestore.dart';

import 'credentials.dart';
import 'database_mock.dart';

Future<void> main(List<String> args) async {
  Log.level = LogLevel.w;
  final FirebaseOptions options = FirebaseOptions(
    apiKey: "AIzaSyDR*********",
    projectId: "cm-*********",
    storageBucket: "cm-*********.appspot.com",
    applicationId: '1:*********:android:*********',
    databaseUrl: 'https://cm-*********.firebaseio.com',
    gcmSenderId: '*********',
  );
  final FirebaseApp app =
      FirebaseApp.withOptions(options, ServiceCredential('mytoken.dat'), null, "MyApp");
  final FirebaseFirestore firestore =
      await FirebaseFirestore.getInstance(app, openDatabase: DatabaseMock.create);
  final QuerySnapshot query = await firestore.collection('foo').get();
  query.documents.forEach(print);
}
