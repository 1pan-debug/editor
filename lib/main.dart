import 'package:flutter/material.dart';

import 'editor_page.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Code Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3367D6),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const EditorPage(),
    );
  }
}
