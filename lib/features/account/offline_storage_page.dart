import 'package:flutter/material.dart';

import '../../services/offline_storage_rebuild_service.dart';
import '../../services/offline_storage_service.dart';

class OfflineStoragePage extends StatefulWidget {
  const OfflineStoragePage({super.key});

  @override
  State<OfflineStoragePage> createState() => _OfflineStoragePageState();
}

class _OfflineStoragePageState extends State<OfflineStoragePage> {
  bool _loading = true;
  bool _saving = false;
  bool _updating = false;
  String? _error;
  String? _message;
  String? _progressLabel;
  int _progressCurrent = 0;
  int _progressTotal = 0;
  List<OfflineStorageVolume> _volumes = const [];
  OfflineStorageTarget _selectedTarget = OfflineStorageTarget.internal;
  OfflineStorageStats _stats = const OfflineStorageStats(
    fileCount: 0,
    bytes: 0,
  );
  OfflineStorageUpdateResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });

    try {
      final target = await OfflineStorageService.getSelectedTarget();
      final volumes = await OfflineStorageService.getVolumes();
      final stats = await OfflineStorageRebuildService.readStats();

      if (!mounted) return;

      setState(() {
        _selectedTarget = target;
        _volumes = volumes;
        _stats = stats;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _selectTarget(OfflineStorageTarget target) async {
    if (_saving || _updating || target == _selectedTarget) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _message = null;
      _lastResult = null;
    });

    try {
      final selection = await OfflineStorageService.selectTarget(target);
      final volumes = await OfflineStorageService.getVolumes();
      final stats = await OfflineStorageRebuildService.readStats();

      if (!mounted) return;

      setState(() {
        _selectedTarget = selection.target;
        _volumes = volumes;
        _stats = stats;
        _saving = false;
        _message = selection.target == OfflineStorageTarget.removable
            ? 'La carte SD est maintenant l’emplacement choisi pour le stockage hors ligne.'
            : 'La mémoire de l’appareil est maintenant l’emplacement choisi pour le stockage hors ligne.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = '$error';
        _saving = false;
      });
    }
  }

  Future<void> _updateOfflineStorage() async {
    if (_updating || _saving) {
      return;
    }

    setState(() {
      _updating = true;
      _error = null;
      _message = null;
      _lastResult = null;
      _progressCurrent = 0;
      _progressTotal = 0;
      _progressLabel = 'Préparation...';
    });

    try {
      final result = await OfflineStorageRebuildService.updateAll(
        onProgress: (progress) {
          if (!mounted) return;

          setState(() {
            _progressCurrent = progress.current;
            _progressTotal = progress.total;
            _progressLabel = progress.label;
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _lastResult = result;
        _stats = OfflineStorageStats(
          fileCount: result.fileCountOnTarget,
          bytes: result.bytesOnTarget,
        );
        _updating = false;
        _progressLabel = null;
        _message = result.failed == 0
            ? 'Le stockage hors ligne est à jour.'
            : 'Mise à jour terminée avec ${result.failed} fichier(s) non disponible(s).';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = '$error';
        _updating = false;
        _progressLabel = null;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 octet';

    const kb = 1024.0;
    const mb = kb * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} Go';
    }

    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} Mo';
    }

    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)} Ko';
    }

    return '$bytes octets';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stockage hors ligne'),
        actions: [
          IconButton(
            onPressed: _loading || _saving || _updating ? null : _load,
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (!OfflineStorageService.isAndroid) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'La gestion mémoire interne / carte SD est disponible sur Android. '
            'Aucun emplacement n’est modifié sur cet appareil.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final internal = OfflineStorageService.findVolumeForTarget(
      _volumes,
      OfflineStorageTarget.internal,
    );

    final removable = OfflineStorageService.findVolumeForTarget(
      _volumes,
      OfflineStorageTarget.removable,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1A2D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF23405E)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF168CFF)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Choisis l’emplacement utilisé par RC Companion pour ses '
                  'fichiers hors ligne. Le bouton de mise à jour recopie '
                  'd’abord les anciens fichiers locaux encore disponibles et '
                  'utilise Google Drive uniquement pour récupérer les fichiers '
                  'manquants. Aucun ancien cache n’est supprimé.',
                  style: TextStyle(color: Color(0xFFB9C5D4), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          _StatusMessage(message: _message!, success: true),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _StatusMessage(message: _error!, success: false),
        ],
        const SizedBox(height: 18),
        const Text(
          'EMPLACEMENT DU STOCKAGE HORS LIGNE',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: .3,
          ),
        ),
        const SizedBox(height: 12),
        if (internal != null)
          _StorageChoiceCard(
            volume: internal,
            selected: _selectedTarget == OfflineStorageTarget.internal,
            busy: _saving || _updating,
            formatBytes: _formatBytes,
            onSelect: () => _selectTarget(OfflineStorageTarget.internal),
          )
        else
          const _UnavailableCard(
            title: 'Mémoire de l’appareil',
            message: 'Android ne retourne actuellement aucun stockage interne.',
            icon: Icons.phone_android_rounded,
          ),
        const SizedBox(height: 12),
        if (removable != null)
          _StorageChoiceCard(
            volume: removable,
            selected: _selectedTarget == OfflineStorageTarget.removable,
            busy: _saving || _updating,
            formatBytes: _formatBytes,
            onSelect: () => _selectTarget(OfflineStorageTarget.removable),
          )
        else
          const _UnavailableCard(
            title: 'Carte SD / stockage amovible',
            message: 'Aucune carte SD amovible n’est actuellement détectée.',
            icon: Icons.sd_storage_rounded,
          ),
        const SizedBox(height: 18),
        _OfflineLibraryCard(
          stats: _stats,
          lastResult: _lastResult,
          updating: _updating,
          progressCurrent: _progressCurrent,
          progressTotal: _progressTotal,
          progressLabel: _progressLabel,
          formatBytes: _formatBytes,
          onUpdate: _updateOfflineStorage,
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF071426),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF23405E)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFF45B86B)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'La mise à jour ne supprime aucun fichier de Google Drive '
                  'et ne supprime pas les anciens fichiers locaux. Elle '
                  'reconstruit uniquement la bibliothèque sur le support '
                  'actuellement sélectionné.',
                  style: TextStyle(color: Color(0xFFB9C5D4), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OfflineLibraryCard extends StatelessWidget {
  const _OfflineLibraryCard({
    required this.stats,
    required this.lastResult,
    required this.updating,
    required this.progressCurrent,
    required this.progressTotal,
    required this.progressLabel,
    required this.formatBytes,
    required this.onUpdate,
  });

  final OfflineStorageStats stats;
  final OfflineStorageUpdateResult? lastResult;
  final bool updating;
  final int progressCurrent;
  final int progressTotal;
  final String? progressLabel;
  final String Function(int) formatBytes;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final progressValue = progressTotal <= 0
        ? null
        : (progressCurrent / progressTotal).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF23405E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.offline_pin_rounded, color: Color(0xFF168CFF)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bibliothèque hors ligne',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoLine(label: 'Fichiers présents', value: '${stats.fileCount}'),
          _InfoLine(label: 'Espace utilisé', value: formatBytes(stats.bytes)),
          if (lastResult != null) ...[
            const SizedBox(height: 6),
            _InfoLine(
              label: 'Disponibles',
              value: '${lastResult!.available}/${lastResult!.totalExpected}',
            ),
            _InfoLine(
              label: 'Recopiés localement',
              value: '${lastResult!.copiedFromLocal}',
            ),
            _InfoLine(
              label: 'Téléchargés Drive',
              value: '${lastResult!.downloaded}',
            ),
            if (lastResult!.failed > 0)
              _InfoLine(
                label: 'Non disponibles',
                value: '${lastResult!.failed}',
              ),
          ],
          if (updating) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progressValue),
            const SizedBox(height: 8),
            Text(
              progressTotal > 0
                  ? '${progressCurrent.clamp(0, progressTotal)}/$progressTotal — ${progressLabel ?? ''}'
                  : progressLabel ?? 'Préparation...',
              style: const TextStyle(
                color: Color(0xFFB9C5D4),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: updating ? null : onUpdate,
            icon: updating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(
              updating
                  ? 'Mise à jour en cours...'
                  : 'Mettre à jour le stockage hors ligne',
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageChoiceCard extends StatelessWidget {
  const _StorageChoiceCard({
    required this.volume,
    required this.selected,
    required this.busy,
    required this.formatBytes,
    required this.onSelect,
  });

  final OfflineStorageVolume volume;
  final bool selected;
  final bool busy;
  final String Function(int) formatBytes;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final title = volume.removable
        ? 'Carte SD / stockage amovible'
        : 'Mémoire de l’appareil';

    final usable = volume.mounted && volume.writable;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? const Color(0xFF168CFF) : const Color(0xFF23405E),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                volume.removable
                    ? Icons.sd_storage_rounded
                    : Icons.phone_android_rounded,
                color: const Color(0xFF168CFF),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              if (selected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF092F67),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFF168CFF)),
                  ),
                  child: const Text(
                    'UTILISÉ ACTUELLEMENT',
                    style: TextStyle(
                      color: Color(0xFF8DBDFF),
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoLine(
            label: 'État',
            value: volume.mounted ? 'Disponible' : volume.state,
          ),
          _InfoLine(label: 'Capacité', value: formatBytes(volume.totalBytes)),
          _InfoLine(
            label: 'Espace libre',
            value: formatBytes(volume.freeBytes),
          ),
          _InfoLine(
            label: 'Écriture',
            value: volume.writable ? 'Autorisée' : 'Non disponible',
          ),
          const SizedBox(height: 8),
          const Text(
            'Dossier RC Companion :',
            style: TextStyle(
              color: Color(0xFFB9C5D4),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            volume.rcCompanionPath,
            style: const TextStyle(color: Color(0xFFB9C5D4), fontSize: 11),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: selected
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Stockage sélectionné'),
                  )
                : FilledButton.icon(
                    onPressed: usable && !busy ? onSelect : null,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt_rounded),
                    label: Text(
                      volume.removable
                          ? 'Utiliser la carte SD'
                          : 'Utiliser la mémoire de l’appareil',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF23405E)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF7F8DA0)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFFB9C5D4),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message, required this.success});

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final color = success
        ? const Color(0xFF45B86B)
        : Theme.of(context).colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF071426),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB9C5D4),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFB9C5D4), fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
