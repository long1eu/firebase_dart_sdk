import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'items_page.dart';

Future<void> main() async {
  await bootstrap();
  runApp(const FlutterfireOnWindowsApp());
}

class FlutterfireOnWindowsApp extends StatelessWidget {
  const FlutterfireOnWindowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterFire on Windows',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      // Follows the system setting (themeMode defaults to ThemeMode.system).
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const ItemsPage(),
    );
  }
}
