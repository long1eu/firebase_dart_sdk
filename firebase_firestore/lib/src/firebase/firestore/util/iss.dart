// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:quiver/iterables.dart';

void main() async {
  final Executor executor = await Executor.create();

  await Future.delayed(const Duration(seconds: 1));
  for (int i in range(10)) {
    executor.sendMessage(Message('$i'));
  }

  await Future.delayed(const Duration(days: 50));
}

class Executor {
  final ServerSocket serverSocket;
  final List<Socket> clients = <Socket>[];

  Executor(this.serverSocket) {
    serverSocket.listen(
      (socket) {
        print('conection from $socket');
        clients.add(socket);
        socket.listen((_) {}, onDone: () {
          clients.remove(socket);
        });
      },
    );
  }

  static Future<Executor> create() async {
    final ServerSocket serverSocket =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

    Isolate.spawn(_spawn, serverSocket.port);

    return Executor(serverSocket);
  }

  void sendMessage(Message message) {
    clients.forEach((socket) {
      socket.add(message.message.codeUnits);
    });
  }

  static void _spawn(int port) async {
    final Socket socket =
        await Socket.connect(InternetAddress.loopbackIPv4, port);

    compute();
    socket.listen((data) {
      Message message = Message(String.fromCharCodes(data));
      print(message.message);
    });

    print('listening');
    await Future.delayed(const Duration(seconds: 4));
    print('finished');
    await socket.close();
  }
}

class Message {
  final String message;

  const Message(this.message);

  @override
  String toString() => 'Message{message: $message}';
}
