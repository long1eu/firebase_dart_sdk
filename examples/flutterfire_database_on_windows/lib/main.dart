import 'package:flutter/material.dart';
import 'package:flutterfire_database_on_windows/bootstrap.dart';
import 'package:flutterfire_database_on_windows/notes_page.dart';

Future<void> main() async {
  await bootstrap();
  runApp(const FlutterfireDatabaseOnWindowsApp());
}

/// The app: one page, [NotesPage].
class FlutterfireDatabaseOnWindowsApp extends StatelessWidget {
  /// Creates the app.
  const FlutterfireDatabaseOnWindowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Database on Windows',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.orange),
      // Follows the system setting (themeMode defaults to ThemeMode.system).
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.orange,
        brightness: Brightness.dark,
      ),
      home: const NotesPage(),
    );
  }
}
