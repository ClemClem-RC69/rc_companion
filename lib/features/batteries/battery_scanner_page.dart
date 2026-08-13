import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:simple_camera_windows/simple_camera_windows.dart';
import 'package:zxing2/qrcode.dart' as zxing;

class BatteryScannerPage extends StatefulWidget {
  const BatteryScannerPage({super.key, this.title = 'Scanner une batterie'});

  final String title;

  @override
  State<BatteryScannerPage> createState() => _BatteryScannerPageState();
}

class _BatteryScannerPageState extends State<BatteryScannerPage> {
  MobileScannerController? _mobileController;

  final SimpleCameraWindows _windowsCamera = SimpleCameraWindows();

  Timer? _windowsScanTimer;
  Uint8List? _windowsLastFrame;
  String _windowsStatus = 'Initialisation de la caméra Windows…';
  bool _windowsCameraStarted = false;
  bool _windowsCaptureRunning = false;
  bool _windowsCameraUnavailable = false;
  bool _isReturningResult = false;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();

    if (_isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startWindowsScanner());
      });
      return;
    }

    _mobileController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isReturningResult || capture.barcodes.isEmpty) {
      return;
    }

    final rawValue = capture.barcodes.first.rawValue?.trim();

    if (rawValue == null || rawValue.isEmpty) {
      return;
    }

    _isReturningResult = true;
    await _mobileController?.stop();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(rawValue);
  }

  Future<void> _startWindowsScanner() async {
    if (!_isWindows || _windowsCameraStarted || _isReturningResult) {
      return;
    }

    if (mounted) {
      setState(() {
        _windowsCameraUnavailable = false;
        _windowsStatus = 'Recherche d’une caméra ou webcam Windows…';
      });
    }

    try {
      await _windowsCamera.initializeCamera();
      await _windowsCamera.startCamera();

      _windowsCameraStarted = true;

      if (mounted) {
        setState(() {
          _windowsStatus =
              'Caméra active. Présente le QR Code devant la webcam.';
        });
      }

      _windowsScanTimer?.cancel();
      _windowsScanTimer = Timer.periodic(
        const Duration(milliseconds: 850),
        (_) => unawaited(_captureAndDecodeWindowsFrame()),
      );

      unawaited(_captureAndDecodeWindowsFrame());
    } catch (error, stackTrace) {
      debugPrint('Scanner QR Windows indisponible : $error');
      debugPrintStack(stackTrace: stackTrace);

      _windowsScanTimer?.cancel();
      _windowsScanTimer = null;
      _windowsCameraStarted = false;

      if (!mounted) return;

      setState(() {
        _windowsCameraUnavailable = true;
        _windowsStatus =
            'Aucune caméra Windows utilisable n’a pu être ouverte. '
            'La caméra peut être absente, désactivée, refusée par Windows '
            'ou incompatible.';
      });
    }
  }

  Future<void> _captureAndDecodeWindowsFrame() async {
    if (!_isWindows ||
        !_windowsCameraStarted ||
        _windowsCaptureRunning ||
        _isReturningResult) {
      return;
    }

    _windowsCaptureRunning = true;

    try {
      final frame = await _windowsCamera.captureFrame();

      if (frame == null || frame.isEmpty || _isReturningResult) {
        return;
      }

      if (mounted) {
        setState(() => _windowsLastFrame = frame);
      }

      final qrValue = _decodeWindowsQr(frame);
      if (qrValue == null || qrValue.isEmpty || _isReturningResult) {
        return;
      }

      _isReturningResult = true;
      _windowsScanTimer?.cancel();
      _windowsScanTimer = null;

      try {
        await _windowsCamera.stopCamera();
      } catch (_) {
        // La caméra peut déjà avoir été fermée par Windows.
      }
      _windowsCameraStarted = false;

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(qrValue);
    } catch (error) {
      // Une image sans QR Code est un cas normal pendant le scan.
      // Les erreurs de capture ponctuelles sont également ignorées afin de
      // laisser les captures suivantes retenter automatiquement.
      debugPrint('Lecture d’une image webcam Windows impossible : $error');
    } finally {
      _windowsCaptureRunning = false;
    }
  }

  String? _decodeWindowsQr(Uint8List frame) {
    try {
      final decoded = img.decodeImage(frame);
      if (decoded == null) {
        return null;
      }

      final rgba = decoded
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.abgr);

      final source = zxing.RGBLuminanceSource(
        decoded.width,
        decoded.height,
        rgba.buffer.asInt32List(rgba.offsetInBytes, rgba.lengthInBytes ~/ 4),
      );

      final bitmap = zxing.BinaryBitmap(zxing.HybridBinarizer(source));
      final result = zxing.QRCodeReader().decode(bitmap);
      return result.text.trim();
    } on zxing.ReaderException {
      return null;
    } catch (error) {
      debugPrint('Décodage QR Windows impossible : $error');
      return null;
    }
  }

  Future<void> _stopWindowsCamera() async {
    _windowsScanTimer?.cancel();
    _windowsScanTimer = null;

    if (!_windowsCameraStarted) {
      return;
    }

    _windowsCameraStarted = false;

    try {
      await _windowsCamera.stopCamera();
    } catch (_) {
      // Fermeture best-effort : Windows peut déjà avoir libéré la webcam.
    }
  }

  @override
  void dispose() {
    _windowsScanTimer?.cancel();

    if (_isWindows) {
      unawaited(_stopWindowsCamera());
    } else {
      _mobileController?.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isWindows) {
      return _buildWindowsScanner(context);
    }

    final controller = _mobileController!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Activer ou désactiver le flash',
            onPressed: controller.toggleTorch,
            icon: const Icon(Icons.flash_on),
          ),
          IconButton(
            tooltip: 'Changer de caméra',
            onPressed: controller.switchCamera,
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: controller, onDetect: _handleDetection),
          const _ScannerOverlay(),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
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
        ],
      ),
    );
  }

  Widget _buildWindowsScanner(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _windowsCameraUnavailable
                        ? Icons.videocam_off_rounded
                        : Icons.qr_code_scanner_rounded,
                    size: 64,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _windowsStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sous Windows, RC Companion ouvre la caméra dans une '
                    'fenêtre dédiée et analyse régulièrement une image de la '
                    'webcam pour rechercher le QR Code de la batterie.',
                    textAlign: TextAlign.center,
                  ),
                  if (_windowsLastFrame != null) ...[
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(
                        _windowsLastFrame!,
                        width: 360,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_windowsCameraUnavailable)
                    FilledButton.icon(
                      onPressed: _startWindowsScanner,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Réessayer la caméra'),
                    )
                  else
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Recherche du QR Code…'),
                      ],
                    ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _stopWindowsCamera();
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.keyboard_rounded),
                    label: const Text('Retour à la sélection manuelle'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Scanner QR Windows : intégration préparée, à valider '
                    'sur un PC Windows équipé d’une webcam.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortestSide = constraints.biggest.shortestSide;
          final scanSize = (shortestSide * 0.72).clamp(240.0, 360.0);

          return Stack(
            children: [
              ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.58),
                  BlendMode.srcOut,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        backgroundBlendMode: BlendMode.dstOut,
                      ),
                    ),
                    Center(
                      child: Container(
                        width: scanSize,
                        height: scanSize,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Center(
                child: Container(
                  width: scanSize,
                  height: scanSize,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
