import 'package:flutter/material.dart';

class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle session')),
      body: const Center(child: Text('Les sessions arriveront ici.', style: TextStyle(fontSize: 22))),
    );
  }
}
