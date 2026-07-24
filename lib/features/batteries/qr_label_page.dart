import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/battery.dart';

class QrLabelPage extends StatefulWidget {
  const QrLabelPage({super.key, required this.battery});

  final Battery battery;

  @override
  State<QrLabelPage> createState() => _QrLabelPageState();
}

class _QrLabelPageState extends State<QrLabelPage> {
  static const _labelFormat = PdfPageFormat(
    50 * PdfPageFormat.mm,
    30 * PdfPageFormat.mm,
    marginAll: 2 * PdfPageFormat.mm,
  );

  bool _isPrinting = false;

  Battery get battery => widget.battery;

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final document = pw.Document();

    document.addPage(
      pw.Page(
        pageFormat: _labelFormat,
        build: (context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 0.8),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            padding: const pw.EdgeInsets.all(6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: battery.id,
                  width: 18 * PdfPageFormat.mm,
                  height: 18 * PdfPageFormat.mm,
                  drawText: false,
                ),
                pw.SizedBox(width: 3 * PdfPageFormat.mm),
                pw.Expanded(
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        battery.id,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (battery.isPaired) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Paire ${battery.pairId}',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return document.save();
  }

  Future<void> _printLabel() async {
    if (_isPrinting) {
      return;
    }

    setState(() {
      _isPrinting = true;
    });

    try {
      // Le PDF est entièrement généré avant l'ouverture de la feuille
      // d'impression. Sur iPadOS, cela évite que la feuille native se
      // referme pendant que le document est encore en cours de construction.
      final pdfBytes = await _buildPdf(_labelFormat);

      await Printing.layoutPdf(
        name: 'Etiquette_${battery.id}.pdf',
        format: _labelFormat,
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
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Étiquette QR Code')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                      data: battery.id,
                      version: QrVersions.auto,
                      size: 220,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      battery.id,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (battery.isPaired) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Paire ${battery.pairId}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '${battery.technology} • ${battery.brand}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${battery.cells} • ${battery.capacity} mAh • '
                      '${battery.cRate}C',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _isPrinting ? null : _printLabel,
            icon: _isPrinting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print),
            label: Text(
              _isPrinting
                  ? 'Ouverture de l’impression...'
                  : 'Imprimer l’étiquette',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Le bouton ouvre la fenêtre d’impression de l’appareil. '
            'L’étiquette PDF mesure 50 × 30 mm.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
