import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'notes_page.dart';

Future<void> main() async {
  await bootstrap();
  runApp(const FlutterfireDatabaseOnLinuxApp());
}

class FlutterfireDatabaseOnLinuxApp extends StatelessWidget {
  const FlutterfireDatabaseOnLinuxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Database on Linux',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.orange),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.orange,
        brightness: Brightness.dark,
      ),
      home: const NotesPage(),
    );
  }
}
