import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'images_page.dart';

Future<void> main() async {
  await bootstrap();
  runApp(const FlutterfireStorageOnLinuxApp());
}

class FlutterfireStorageOnLinuxApp extends StatelessWidget {
  const FlutterfireStorageOnLinuxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Storage on Linux',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const ImagesPage(),
    );
  }
}
