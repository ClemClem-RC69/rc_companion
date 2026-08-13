import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/battery.dart';

class QrLabelPage extends StatefulWidget {
  const QrLabelPage({
    super.key,
    required this.battery,
    this.availableBatteries = const [],
  });

  final Battery battery;
  final List<Battery> availableBatteries;

  @override
  State<QrLabelPage> createState() => _QrLabelPageState();
}

class _QrLabelPageState extends State<QrLabelPage> {
  static const _a4Format = PdfPageFormat.a4;
  static const double _labelWidth = 50 * PdfPageFormat.mm;
  static const double _labelHeight = 30 * PdfPageFormat.mm;
  static const double _pageMargin = 10 * PdfPageFormat.mm;
  static const double _horizontalGap = 4 * PdfPageFormat.mm;
  static const double _verticalGap = 3 * PdfPageFormat.mm;
  static const int _columns = 3;
  static const int _rows = 8;
  static const int _labelsPerPage = _columns * _rows;

  bool _isPrinting = false;
  bool _selectAll = true;
  late final Set<String> _selectedBatteryIds;

  Battery get battery => widget.battery;

  List<Battery> get _allBatteries {
    final batteries = widget.availableBatteries.isEmpty
        ? <Battery>[battery]
        : List<Battery>.from(widget.availableBatteries);

    batteries.sort((a, b) => a.id.compareTo(b.id));
    return batteries;
  }

  List<Battery> get _selectedBatteries {
    return _allBatteries
        .where((item) => _selectedBatteryIds.contains(item.id))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _selectedBatteryIds = _allBatteries.map((item) => item.id).toSet();
  }

  pw.Widget _buildLabel(Battery item) {
    return pw.Container(
      width: _labelWidth,
      height: _labelHeight,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.7),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.all(5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: item.id,
            width: 18 * PdfPageFormat.mm,
            height: 18 * PdfPageFormat.mm,
            drawText: false,
          ),
          pw.SizedBox(width: 2.5 * PdfPageFormat.mm),
          pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  item.id,
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '${item.cells} - ${item.capacity} mAh - ${item.cRate}C',
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
                if (item.isPaired) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Paire ${item.pairId}',
                    maxLines: 1,
                    style: pw.TextStyle(
                      fontSize: 6.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildSingleLabelPdf() async {
    final document = pw.Document();

    document.addPage(
      pw.Page(
        pageFormat: _a4Format,
        margin: const pw.EdgeInsets.all(_pageMargin),
        build: (context) {
          return pw.Align(
            alignment: pw.Alignment.topLeft,
            child: _buildLabel(battery),
          );
        },
      ),
    );

    return document.save();
  }

  Future<Uint8List> _buildSheetPdf(List<Battery> batteries) async {
    final document = pw.Document();

    for (var start = 0; start < batteries.length; start += _labelsPerPage) {
      final end = (start + _labelsPerPage).clamp(0, batteries.length);
      final pageBatteries = batteries.sublist(start, end);

      document.addPage(
        pw.Page(
          pageFormat: _a4Format,
          margin: const pw.EdgeInsets.all(_pageMargin),
          build: (context) {
            return pw.Wrap(
              spacing: _horizontalGap,
              runSpacing: _verticalGap,
              children: [for (final item in pageBatteries) _buildLabel(item)],
            );
          },
        ),
      );
    }

    return document.save();
  }

  Future<void> _printSingleLabel() async {
    if (_isPrinting) {
      return;
    }

    setState(() => _isPrinting = true);

    try {
      final pdfBytes = await _buildSingleLabelPdf();

      await Printing.layoutPdf(
        name: 'Etiquette_${battery.id}.pdf',
        format: _a4Format,
        dynamicLayout: false,
        onLayout: (_) async => pdfBytes,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Impression impossible : $error')));
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  Future<void> _printSheet() async {
    if (_isPrinting) {
      return;
    }

    final selected = _selectedBatteries;

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionne au moins une batterie.')),
      );
      return;
    }

    setState(() => _isPrinting = true);

    try {
      final pdfBytes = await _buildSheetPdf(selected);

      await Printing.layoutPdf(
        name: 'Planche_QR_${selected.length}_batteries.pdf',
        format: _a4Format,
        dynamicLayout: false,
        onLayout: (_) async => pdfBytes,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Impression impossible : $error')));
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  void _toggleSelectAll(bool? selected) {
    final shouldSelectAll = selected ?? false;

    setState(() {
      _selectAll = shouldSelectAll;
      _selectedBatteryIds.clear();

      if (shouldSelectAll) {
        _selectedBatteryIds.addAll(_allBatteries.map((item) => item.id));
      }
    });
  }

  void _toggleBattery(Battery item, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedBatteryIds.add(item.id);
      } else {
        _selectedBatteryIds.remove(item.id);
      }

      _selectAll = _selectedBatteryIds.length == _allBatteries.length;
    });
  }

  Widget _buildPreviewCard() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: battery.id,
                version: QrVersions.auto,
                size: 180,
              ),
              const SizedBox(height: 14),
              Text(
                battery.id,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (battery.isPaired) ...[
                const SizedBox(height: 6),
                Text(
                  'Paire ${battery.pairId}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '${battery.cells} • ${battery.capacity} mAh • ${battery.cRate}C',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionCard() {
    final allBatteries = _allBatteries;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              value: _selectAll,
              onChanged: _isPrinting ? null : _toggleSelectAll,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Toutes les batteries (${allBatteries.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('24 étiquettes maximum par feuille A4.'),
            ),
            const Divider(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allBatteries.length,
                itemBuilder: (context, index) {
                  final item = allBatteries[index];

                  return CheckboxListTile(
                    value: _selectedBatteryIds.contains(item.id),
                    onChanged: _isPrinting
                        ? null
                        : (value) => _toggleBattery(item, value),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.id),
                    subtitle: Text(
                      '${item.technology} • ${item.cells} • '
                      '${item.capacity} mAh • ${item.cRate}C',
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isPrinting ? null : _printSheet,
              icon: _isPrinting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.grid_view),
              label: Text(
                _isPrinting
                    ? 'Préparation de l’impression...'
                    : 'Imprimer ${_selectedBatteryIds.length} étiquette(s)',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPrintSheet = widget.availableBatteries.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Étiquettes QR Code')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildPreviewCard(),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _isPrinting ? null : _printSingleLabel,
            icon: const Icon(Icons.print),
            label: const Text('Imprimer cette étiquette sur une feuille A4'),
          ),
          const SizedBox(height: 8),
          const Text(
            'L’étiquette 50 × 30 mm sera placée en haut à gauche de la feuille '
            'afin de limiter le gaspillage.',
            textAlign: TextAlign.center,
          ),
          if (canPrintSheet) ...[
            const SizedBox(height: 24),
            Text(
              'Planche d’étiquettes',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _buildSelectionCard(),
          ],
        ],
      ),
    );
  }
}
