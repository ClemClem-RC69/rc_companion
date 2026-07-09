import 'package:flutter/material.dart';

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entretiens')),
      body: const Center(child: Text('Les entretiens arriveront ici.', style: TextStyle(fontSize: 22))),
    );
  }
}
