import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/model_document.dart';
import '../../models/rc_model.dart';
import '../../services/model_document_service.dart';
import 'widgets/model_radio_controls_tab.dart';
import 'widgets/model_radio_setup_tab.dart';
import 'widgets/model_setup_tab.dart';
import 'widgets/model_history_tab.dart';
import '../../models/radio.dart';
import '../../services/radio_service.dart';

class ModelDetailPage extends StatefulWidget {
  const ModelDetailPage({
    super.key,
    required this.modelId,
    required this.model,
  });

  final String modelId;
  final RcModel model;

  @override
  State<ModelDetailPage> createState() => _ModelDetailPageState();
}

class _ModelDetailPageState extends State<ModelDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController tabController;

  List<ModelDocument> documents = [];

  bool isLoadingDocuments = true;
  bool isAddingDocument = false;
  String? documentsError;

  @override
  void initState() {
    super.initState();

    tabController = TabController(
      length: 6,
      vsync: this,
    );

    loadDocuments();
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  Future<void> loadDocuments() async {
    setState(() {
      isLoadingDocuments = true;
      documentsError = null;
    });

    try {
      final result = await ModelDocumentService.getDocuments(
        widget.modelId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        documents = result;
        isLoadingDocuments = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLoadingDocuments = false;
        documentsError =
            'Impossible de charger les documents.\n$error';
      });
    }
  }

  Future<void> addDocument() async {
    final documentType = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Type de document'),
          children: [
            _documentTypeOption(
              dialogContext,
              value: 'Notice',
              icon: Icons.menu_book_outlined,
            ),
            _documentTypeOption(
              dialogContext,
              value: 'Vue éclatée',
              icon: Icons.account_tree_outlined,
            ),
            _documentTypeOption(
              dialogContext,
              value: 'Manuel ESC',
              icon: Icons.electric_bolt_outlined,
            ),
            _documentTypeOption(
              dialogContext,
              value: 'Manuel radio',
              icon: Icons.settings_remote_outlined,
            ),
            _documentTypeOption(
              dialogContext,
              value: 'Autre',
              icon: Icons.insert_drive_file_outlined,
            ),
          ],
        );
      },
    );

    if (documentType == null) {
      return;
    }

    setState(() {
      isAddingDocument = true;
    });

    try {
      var document = await ModelDocumentService.addDocument(
        modelId: widget.modelId,
        documentType: documentType,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        documents.add(document);
        isAddingDocument = false;
      });

      final customName = await _showRenameDialog(
        document,
        title: 'Nom du document',
        helperText:
            'Tu peux conserver le nom d’origine ou saisir un nom plus clair.',
      );

      if (customName != null &&
          customName.trim().isNotEmpty &&
          customName.trim() != document.documentName) {
        try {
          document = await ModelDocumentService.renameDocument(
            document: document,
            newName: customName,
          );

          if (!mounted) {
            return;
          }

          final index = documents.indexWhere(
            (item) => item.id == document.id,
          );

          if (index != -1) {
            setState(() {
              documents[index] = document;
            });
          }
        } catch (error) {
          if (!mounted) {
            return;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Le document a été ajouté, mais son nom '
                'n’a pas pu être modifié : $error',
              ),
            ),
          );

          return;
        }
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document ajouté'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isAddingDocument = false;
      });

      final message = error.toString();

      if (message.contains('Aucun document sélectionné')) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible d’ajouter le document : $error',
          ),
        ),
      );
    }
  }

  SimpleDialogOption _documentTypeOption(
    BuildContext dialogContext, {
    required String value,
    required IconData icon,
  }) {
    return SimpleDialogOption(
      onPressed: () {
        Navigator.pop(dialogContext, value);
      },
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Text(value),
        ],
      ),
    );
  }

  Future<String?> _showRenameDialog(
    ModelDocument document, {
    String title = 'Renommer le document',
    String? helperText,
  }) async {
    final controller = TextEditingController(
      text: document.documentName,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: 'Nom affiché',
              helperText: helperText,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              final cleanValue = value.trim();

              if (cleanValue.isNotEmpty) {
                Navigator.pop(dialogContext, cleanValue);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final cleanValue = controller.text.trim();

                if (cleanValue.isEmpty) {
                  return;
                }

                Navigator.pop(dialogContext, cleanValue);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );


    return result;
  }

  Future<void> renameDocument(
    ModelDocument document,
  ) async {
    final newName = await _showRenameDialog(document);

    if (newName == null) {
      return;
    }

    final cleanName = newName.trim();

    if (cleanName.isEmpty ||
        cleanName == document.documentName) {
      return;
    }

    try {
      final renamedDocument =
          await ModelDocumentService.renameDocument(
        document: document,
        newName: cleanName,
      );

      if (!mounted) {
        return;
      }

      final index = documents.indexWhere(
        (item) => item.id == document.id,
      );

      if (index == -1) {
        await loadDocuments();
        return;
      }

      setState(() {
        documents[index] = renamedDocument;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document renommé'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de renommer le document : $error',
          ),
        ),
      );
    }
  }

  Future<void> openDocument(
    ModelDocument document,
  ) async {
    try {
      final signedUrl =
          await ModelDocumentService.openDocument(document);

      if (!mounted) {
        return;
      }

      if (_isImageDocument(document)) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ModelImagePage(
              title: document.documentName,
              signedUrl: signedUrl,
            ),
          ),
        );

        return;
      }

      if (_isPdfDocument(document)) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ModelPdfPage(
              title: document.documentName,
              signedUrl: signedUrl,
            ),
          ),
        );

        return;
      }

      throw Exception(
        'Ce format de document n’est pas pris en charge.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible d’ouvrir le document : $error',
          ),
        ),
      );
    }
  }

  Future<void> confirmDeleteDocument(
    ModelDocument document,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer le document'),
          content: Text(
            'Veux-tu vraiment supprimer '
            '"${document.documentName}" ?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      await ModelDocumentService.deleteDocument(document);

      if (!mounted) {
        return;
      }

      setState(() {
        documents.removeWhere(
          (item) => item.id == document.id,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document supprimé'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de supprimer le document : $error',
          ),
        ),
      );
    }
  }

  String _documentExtension(ModelDocument document) {
    final path = document.storagePath
        .toLowerCase()
        .split('?')
        .first
        .trim();

    final dotIndex = path.lastIndexOf('.');

    if (dotIndex == -1 || dotIndex == path.length - 1) {
      return '';
    }

    return path.substring(dotIndex + 1);
  }

  bool _isPdfDocument(ModelDocument document) {
    return _documentExtension(document) == 'pdf';
  }

  bool _isImageDocument(ModelDocument document) {
    final extension = _documentExtension(document);

    return extension == 'jpg' ||
        extension == 'jpeg' ||
        extension == 'png' ||
        extension == 'webp';
  }

  IconData _iconForDocument(
    ModelDocument document,
  ) {
    if (_isImageDocument(document)) {
      return Icons.image_outlined;
    }

    return _iconForDocumentType(document.documentType);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.model.name),
        bottom: TabBar(
          controller: tabController,
          isScrollable: true,
          tabs: const [
            Tab(
              icon: Icon(Icons.info_outline),
              text: 'Informations',
            ),
            Tab(
              icon: Icon(Icons.folder_outlined),
              text: 'Documents',
            ),
            Tab(
              icon: Icon(Icons.tune),
              text: 'Setup',
            ),
            Tab(
              icon: Icon(Icons.settings_remote_outlined),
              text: 'Réglages radio',
            ),
            Tab(
              icon: Icon(Icons.gamepad_outlined),
              text: 'Commandes radio',
            ),
            Tab(
              icon: Icon(Icons.history),
              text: 'Historique',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: [
          _InformationTab(model: widget.model),
          buildDocumentsTab(),
          ModelSetupTab(
            modelId: widget.modelId,
          ),
          ModelRadioSetupTab(
            modelId: widget.modelId,
            model: widget.model,
          ),
          ModelRadioControlsTab(
            modelId: widget.modelId,
            model: widget.model,
          ),
          ModelHistoryTab(
            model: widget.model,
          ),
        ],
      ),
    );
  }

  Widget buildDocumentsTab() {
    if (isLoadingDocuments) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (documentsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 54,
              ),
              const SizedBox(height: 16),
              Text(
                documentsError!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: loadDocuments,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: loadDocuments,
          child: documents.isEmpty
              ? ListView(
                  physics:
                      const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: const [
                    SizedBox(height: 120),
                    Icon(
                      Icons.folder_open_outlined,
                      size: 72,
                    ),
                    SizedBox(height: 16),
                    Center(
                      child: Text(
                        'Aucun document',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Ajoute une notice, une vue éclatée, '
                        'un PDF ou une image.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    100,
                  ),
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final document = documents[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(
                          _iconForDocument(document),
                          size: 34,
                        ),
                        title: Text(
                          document.documentName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          document.documentType,
                        ),
                        onTap: () => openDocument(document),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Options',
                          onSelected: (value) {
                            if (value == 'open') {
                              openDocument(document);
                            } else if (value == 'rename') {
                              renameDocument(document);
                            } else if (value == 'delete') {
                              confirmDeleteDocument(document);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'open',
                              child: Row(
                                children: [
                                  Icon(Icons.open_in_new),
                                  SizedBox(width: 10),
                                  Text('Ouvrir'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined),
                                  SizedBox(width: 10),
                                  Text('Renommer'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline),
                                  SizedBox(width: 10),
                                  Text('Supprimer'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add-model-document',
            onPressed:
                isAddingDocument ? null : addDocument,
            icon: isAddingDocument
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.add),
            label: Text(
              isAddingDocument
                  ? 'Ajout...'
                  : 'Ajouter un document',
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconForDocumentType(String type) {
    switch (type) {
      case 'Notice':
        return Icons.menu_book_outlined;
      case 'Vue éclatée':
        return Icons.account_tree_outlined;
      case 'Manuel ESC':
        return Icons.electric_bolt_outlined;
      case 'Manuel radio':
        return Icons.settings_remote_outlined;
      case 'Autre':
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

class _InformationTab extends StatelessWidget {
  const _InformationTab({
    required this.model,
  });

  final RcModel model;

  Future<RcRadio?> _loadSelectedRadio() async {
    final radioId = model.radioId;

    if (radioId == null || radioId.trim().isEmpty) {
      return null;
    }

    final radios = await RadioService().fetchRadios();

    for (final radio in radios) {
      if (radio.id == radioId) {
        return radio;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isElectric = model.motorization == 'Électrique';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ModelPhotoHeader(model: model),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Icon(
              _iconForCategory(model.category),
              size: 36,
            ),
            title: Text(
              model.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '${model.brand} • '
              '${model.category} • ${model.scale}',
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Informations',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        _infoCard(
          icon: Icons.category,
          title: 'Catégorie',
          value: model.category,
        ),
        if (model.discipline.isNotEmpty)
          _infoCard(
            icon: Icons.sports_motorsports,
            title: 'Discipline',
            value: model.discipline,
          ),
        _infoCard(
          icon: Icons.settings,
          title: 'Motorisation',
          value: model.motorization,
        ),
        _infoCard(
          icon: Icons.straighten,
          title: 'Échelle',
          value: model.scale,
        ),
        if (model.weightKg != null)
          _infoCard(
            icon: Icons.monitor_weight_outlined,
            title: 'Poids',
            value: model.formattedWeight,
          ),
        FutureBuilder<RcRadio?>(
          future: _loadSelectedRadio(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Card(
                child: ListTile(
                  leading: Icon(Icons.settings_remote_outlined),
                  title: Text('Radio utilisée'),
                  trailing: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                ),
              );
            }

            if (snapshot.hasError) {
              return _infoCard(
                icon: Icons.settings_remote_outlined,
                title: 'Radio utilisée',
                value: 'Impossible à charger',
              );
            }

            final radio = snapshot.data;

            return _infoCard(
              icon: Icons.settings_remote_outlined,
              title: 'Radio utilisée',
              value: radio?.fullName ?? 'Aucune radio',
            );
          },
        ),
        if (isElectric) ...[
          const SizedBox(height: 20),
          const Text(
            'Configuration électrique',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          _infoCard(
            icon: Icons.battery_charging_full,
            title: 'Nombre de batteries',
            value: '${model.batteryCount}',
          ),
          _infoCard(
            icon: Icons.flash_on,
            title: 'Configuration maximale',
            value: model.maxCells,
          ),
        ],
      ],
    );
  }

  static Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 260,
          ),
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  static IconData _iconForCategory(String category) {
    switch (category) {
      case 'Bateau':
        return Icons.sailing;
      case 'Avion':
        return Icons.flight;
      case 'Hélicoptère':
        return Icons.air;
      case 'Drone':
        return Icons.flight_takeoff;
      case 'Voiture':
      default:
        return Icons.directions_car;
    }
  }
}

class ModelPdfPage extends StatelessWidget {
  const ModelPdfPage({
    super.key,
    required this.title,
    required this.signedUrl,
  });

  final String title;
  final String signedUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: PdfViewer.uri(
        Uri.parse(signedUrl),
      ),
    );
  }
}

class ModelImagePage extends StatelessWidget {
  const ModelImagePage({
    super.key,
    required this.title,
    required this.signedUrl,
  });

  final String title;
  final String signedUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        alignment: Alignment.center,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: Image.network(
            signedUrl,
            fit: BoxFit.contain,
            loadingBuilder: (
              context,
              child,
              loadingProgress,
            ) {
              if (loadingProgress == null) {
                return child;
              }

              return const Center(
                child: CircularProgressIndicator(),
              );
            },
            errorBuilder: (_, __, ___) {
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
}

class _ModelPhotoHeader extends StatelessWidget {
  const _ModelPhotoHeader({
    required this.model,
  });

  final RcModel model;

  @override
  Widget build(BuildContext context) {
    final photoUrl = model.photoUrl;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.infinity,
        height: 280,
        child: photoUrl != null &&
                photoUrl.trim().isNotEmpty
            ? Container(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                alignment: Alignment.center,
                child: Image.network(
                  photoUrl,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                  loadingBuilder: (
                    context,
                    child,
                    loadingProgress,
                  ) {
                    if (loadingProgress == null) {
                      return child;
                    }

                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  },
                  errorBuilder: (_, __, ___) {
                    return _EmptyModelPhoto(
                      category: model.category,
                    );
                  },
                ),
              )
            : _EmptyModelPhoto(
                category: model.category,
              ),
      ),
    );
  }
}

class _EmptyModelPhoto extends StatelessWidget {
  const _EmptyModelPhoto({
    required this.category,
  });

  final String category;

  IconData get icon {
    switch (category) {
      case 'Bateau':
        return Icons.sailing;
      case 'Avion':
        return Icons.flight;
      case 'Hélicoptère':
        return Icons.air;
      case 'Drone':
        return Icons.flight_takeoff;
      case 'Voiture':
      default:
        return Icons.directions_car;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 72,
          ),
          const SizedBox(height: 12),
          const Text('Aucune photo'),
        ],
      ),
    );
  }
}