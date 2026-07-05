import 'package:flutter/material.dart';

class ModelsPage extends StatelessWidget {
  const ModelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes modèles'),
      ),
      body: const Center(
        child: Text(
          'Liste des modèles RC',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}