import 'dart:async';

import 'package:firebase_firestore/firebase_firestore.dart';
import 'package:firebase_flutter/firebase_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runFirebaseApp(
      app: const MaterialApp(title: 'Firestore Example', home: MyHomePage()));
}

class MessageList extends StatelessWidget {
  const MessageList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('messages').snapshots,
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (!snapshot.hasData) {
          return const Text('Loading...');
        }
        final int messageCount = snapshot.data.documents.length;
        return ListView.builder(
          itemCount: messageCount,
          itemBuilder: (_, int index) {
            final DocumentSnapshot document = snapshot.data.documents[index];
            return ListTile(
              title: Text(
                  document.getString('message') ?? '<No message retrieved>'),
              subtitle: Text('Message ${index + 1} of $messageCount'),
            );
          },
        );
      },
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage();

  CollectionReference get messages =>
      FirebaseFirestore.instance.collection('messages');

  Future<void> _addMessage() async {
    await messages.add(<String, dynamic>{
      'message': 'Hello world!',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firestore Example'),
      ),
      body: const MessageList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMessage,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
