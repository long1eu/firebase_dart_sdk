// Copyright 2017, the Chromium project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_auth_dart/firebase_auth_dart.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:firebase_core_dart/firebase_core_dart.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart' show isDesktop;
import 'package:flutter/material.dart';

Future<void> main() async {
  if (isDesktop) {
    await FirebaseCoreDart.register(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyBQgB5s3n8WvyCOxhCws-RVf3C-6VnGg0A',
        databaseURL: 'https://flutter-sdk.firebaseio.com',
        projectID: 'flutter-sdk',
        storageBucket: 'flutter-sdk.appspot.com',
        gcmSenderID: '233259864964',
        googleAppID:
            '1:233259864964:macos:0bdc69800dd31cde15627229f39a6379865e8be1',
      ),
    );
    await FirebaseAuthDart.register();
    await FirestoreDart.register();
  }

  runApp(
    MaterialApp(
      title: 'Firestore Example',
      home: MyHomePage(firestore: Firestore.instance),
    ),
  );
}

class MessageList extends StatelessWidget {
  const MessageList({Key key, @required this.firestore}) : super(key: key);

  final Firestore firestore;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('messages')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (!snapshot.hasData) {
          return const Text('Loading...');
        }

        final int messageCount = snapshot.data.documents.length;
        return ListView.builder(
          itemCount: messageCount,
          itemBuilder: (_, int index) {
            final DocumentSnapshot document = snapshot.data.documents[index];
            final dynamic message = document['message'];
            return ListTile(
              trailing: IconButton(
                onPressed: () => document.reference.delete(),
                icon: Icon(Icons.delete),
              ),
              title: Text(
                message != null ? message.toString() : '<No message retrieved>',
              ),
              subtitle: Text('Message ${index + 1} of $messageCount'),
            );
          },
        );
      },
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({Key key, @required this.firestore}) : super(key: key);

  final Firestore firestore;

  CollectionReference get messages => firestore.collection('messages');

  Future<void> _addMessage() async {
    await messages.add(<String, dynamic>{
      'message': 'Hello world!',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _runTransaction() async {
    await firestore.runTransaction((Transaction transaction) async {
      final QuerySnapshot allDocs =
          await firestore.collection('messages').getDocuments();
      final List<DocumentSnapshot> toBeRetrieved =
          allDocs.documents.sublist(allDocs.documents.length ~/ 2);
      final List<DocumentSnapshot> toBeDeleted =
          allDocs.documents.sublist(0, allDocs.documents.length ~/ 2);
      await Future.forEach(toBeDeleted, (DocumentSnapshot snapshot) async {
        await transaction.delete(snapshot.reference);
      });

      await Future.forEach(toBeRetrieved, (DocumentSnapshot snapshot) async {
        await transaction.update(snapshot.reference, <String, dynamic>{
          'message': 'Updated from Transaction',
          'created_at': FieldValue.serverTimestamp()
        });
      });
    });

    await Future.forEach(List<int>.generate(2, (int index) => index),
        (int item) async {
      await firestore.runTransaction((Transaction transaction) async {
        await Future.forEach(List<int>.generate(10, (int index) => index),
            (int item) async {
          await transaction.set(
              firestore.collection('messages').document(), <String, dynamic>{
            'message': 'Created from Transaction $item',
            'created_at': FieldValue.serverTimestamp()
          });
        });
      });
    });
  }

  Future<void> _runBatchWrite() async {
    final WriteBatch batchWrite = firestore.batch();
    final QuerySnapshot querySnapshot = await firestore
        .collection('messages')
        .orderBy('created_at')
        .limit(12)
        .getDocuments();
    querySnapshot.documents
        .sublist(0, querySnapshot.documents.length - 3)
        .forEach((DocumentSnapshot doc) {
      batchWrite.updateData(doc.reference, <String, dynamic>{
        'message': 'Batched message',
        'created_at': FieldValue.serverTimestamp()
      });
    });

    batchWrite
      ..setData(
        firestore.collection('messages').document(),
        <String, dynamic>{
          'message': 'Batched message created',
          'created_at': FieldValue.serverTimestamp()
        },
      )
      ..delete(
          querySnapshot.documents[querySnapshot.documents.length - 2].reference)
      ..delete(querySnapshot.documents.last.reference);
    await batchWrite.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firestore Example'),
        actions: <Widget>[
          FlatButton(
            onPressed: _runTransaction,
            child: const Text('Run Transaction'),
          ),
          FlatButton(
            onPressed: _runBatchWrite,
            child: const Text('Batch Write'),
          )
        ],
      ),
      body: MessageList(firestore: firestore),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMessage,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
