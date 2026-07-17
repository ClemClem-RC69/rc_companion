import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BatteryScannerPage extends StatefulWidget {
  const BatteryScannerPage({super.key});

  @override
  State<BatteryScannerPage> createState() => _BatteryScannerPageState();
}

class _BatteryScannerPageState extends State<BatteryScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _hasScanned = false;

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_hasScanned) {
      return;
    }

    String? scannedValue;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();

      if (value != null && value.isNotEmpty) {
        scannedValue = value;
        break;
      }
    }

    if (scannedValue == null) {
      return;
    }

    _hasScanned = true;
    await _controller.stop();

    if (!mounted) {
      return;
    }

    Navigator.pop(context, scannedValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scanner une batterie'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _controller.toggleTorch,
            tooltip: 'Activer ou désactiver la lampe',
            icon: const Icon(Icons.flash_on),
          ),
          IconButton(
            onPressed: _controller.switchCamera,
            tooltip: 'Changer de caméra',
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetection,
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _ScannerOverlayPainter(),
            ),
          ),
          const SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 36),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.all(
                      Radius.circular(14),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Text(
                      'Place le QR Code de la batterie dans le cadre.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cutOutSize = size.shortestSide * 0.62;
    final left = (size.width - cutOutSize) / 2;
    final top = (size.height - cutOutSize) / 2;
    final cutOutRect = Rect.fromLTWH(
      left,
      top,
      cutOutSize,
      cutOutSize,
    );

    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(
          cutOutRect,
          const Radius.circular(18),
        ),
      );

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black54,
    );

    const borderLength = 30.0;
    const borderWidth = 4.0;

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final right = cutOutRect.right;
    final bottom = cutOutRect.bottom;

    canvas.drawLine(
      Offset(left, top + borderLength),
      Offset(left, top),
      borderPaint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left + borderLength, top),
      borderPaint,
    );
    canvas.drawLine(
      Offset(right - borderLength, top),
      Offset(right, top),
      borderPaint,
    );
    canvas.drawLine(
      Offset(right, top),
      Offset(right, top + borderLength),
      borderPaint,
    );
    canvas.drawLine(
      Offset(left, bottom - borderLength),
      Offset(left, bottom),
      borderPaint,
    );
    canvas.drawLine(
      Offset(left, bottom),
      Offset(left + borderLength, bottom),
      borderPaint,
    );
    canvas.drawLine(
      Offset(right - borderLength, bottom),
      Offset(right, bottom),
      borderPaint,
    );
    canvas.drawLine(
      Offset(right, bottom),
      Offset(right, bottom - borderLength),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
