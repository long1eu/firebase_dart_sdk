import 'package:firebase_firestore/firebase_firestore.dart';
import 'package:firebase_flutter/firebase_flutter.dart';
import 'package:flutter/material.dart';

void main() =>
    runFirebaseApp(MyApp(), googleServicesKey: 'res/google-services.json');

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.document('rooms/1').snapshots,
          builder:
              (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            switch (snapshot.connectionState) {
              case ConnectionState.none:
                return const Text('Select lot');
              case ConnectionState.waiting:
                return const Text('Awaiting bids...');
              case ConnectionState.active:
                return Text('\$${snapshot.data}');
              case ConnectionState.done:
                return Text('\$${snapshot.data} (closed)');
            }
          },
        ),
      ),
    );
  }
}
