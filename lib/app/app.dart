import 'package:flutter/material.dart';

import '../design/companion_theme.dart';
import 'branding.dart';

class CompanionFocusApp extends StatelessWidget {
  const CompanionFocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Branding.name,
      theme: CompanionTheme.light,
      darkTheme: CompanionTheme.dark,
      home: Scaffold(
        appBar: AppBar(title: const Text(Branding.name)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(CompanionTheme.pageInset),
            child: Text(
              'Focus timer development preview',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
  }
}
