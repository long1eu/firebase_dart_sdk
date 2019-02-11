import 'package:firebase_firestore/firebase_firestore.dart';
import 'package:firebase_common/firebase_common.dart';
import 'credentials.dart';
import 'local_db.dart';

void main(List<String> args) async {
  Log.level = LogLevel.w;
  final options = FirebaseOptions(
    apiKey: "AIzaSyDR*********",
    projectId: "cm-*********",
    storageBucket: "cm-*********.appspot.com",
    applicationId: '1:*********:android:*********',
    databaseUrl: 'https://cm-*********.firebaseio.com',
    gcmSenderId: '*********',
  );
  final app = FirebaseApp.withOptions(
      options, ServiceCredential('mytoken.dat'), null, "MyApp");
  final firestore =
      await FirebaseFirestore.getInstance(app, openDatabase: LocalDb.create);
  final query = await firestore.collection('foo').get();
  query.documents.forEach(print);
}
