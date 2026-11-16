import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'items_page.dart';

Future<void> main() async {
  await bootstrap();
  runApp(const FlutterfireOnLinuxApp());
}

class FlutterfireOnLinuxApp extends StatelessWidget {
  const FlutterfireOnLinuxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterFire on Linux',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const ItemsPage(),
    );
  }
}
