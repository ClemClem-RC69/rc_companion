import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

enum RadioManualViewerAction { replace, delete }

class RadioManualViewerPage extends StatelessWidget {
  const RadioManualViewerPage({
    super.key,
    required this.path,
    required this.filename,
  });

  final String path;
  final String filename;

  @override
  Widget build(BuildContext context) {
    final extension = _extension(filename);
    final isPdf = extension == 'pdf';

    return Scaffold(
      appBar: AppBar(
        title: Text(filename),
        actions: [
          PopupMenuButton<RadioManualViewerAction>(
            tooltip: 'Options du manuel',
            onSelected: (action) async {
              if (action == RadioManualViewerAction.replace) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Remplacer le manuel'),
                    content: Text(
                      'Veux-tu remplacer le manuel « $filename » par un autre fichier ?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Annuler'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Remplacer'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && context.mounted) {
                  Navigator.of(context).pop(RadioManualViewerAction.replace);
                }
                return;
              }

              if (action == RadioManualViewerAction.delete) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Supprimer le manuel'),
                    content: Text(
                      'Supprimer le manuel « $filename » ?\n\n'
                      'Cette action supprimera le manuel associé à cette radio.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Annuler'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFB3261E),
                        ),
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Supprimer'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && context.mounted) {
                  Navigator.of(context).pop(RadioManualViewerAction.delete);
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<RadioManualViewerAction>(
                value: RadioManualViewerAction.replace,
                child: Row(
                  children: [
                    Icon(Icons.upload_file_outlined),
                    SizedBox(width: 12),
                    Text('Remplacer le manuel'),
                  ],
                ),
              ),
              PopupMenuItem<RadioManualViewerAction>(
                value: RadioManualViewerAction.delete,
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined),
                    SizedBox(width: 12),
                    Text('Supprimer le manuel'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: isPdf
          ? PdfViewer.file(path)
          : Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Text(
                        'Impossible d’afficher cette image.',
                        style: TextStyle(color: Colors.white),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  String _extension(String value) {
    final clean = value.trim().toLowerCase();
    final dot = clean.lastIndexOf('.');
    if (dot == -1 || dot == clean.length - 1) {
      return '';
    }
    return clean.substring(dot + 1);
  }
}
