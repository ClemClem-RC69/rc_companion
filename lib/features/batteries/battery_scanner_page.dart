import 'dart:async';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing2/qrcode.dart' as zxing;

class BatteryScannerPage extends StatefulWidget {
  const BatteryScannerPage({super.key, this.title = 'Scanner une batterie'});

  final String title;

  @override
  State<BatteryScannerPage> createState() => _BatteryScannerPageState();
}

class _BatteryScannerPageState extends State<BatteryScannerPage> {
  MobileScannerController? _mobileController;

  int _windowsCameraId = -1;
  Size? _windowsPreviewSize;
  Timer? _windowsScanTimer;
  StreamSubscription<CameraErrorEvent>? _windowsErrorSubscription;
  StreamSubscription<CameraClosingEvent>? _windowsClosingSubscription;

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

    await _disposeWindowsCamera();

    if (!mounted) {
      return;
    }

    setState(() {
      _windowsCameraUnavailable = false;
      _windowsStatus = 'Recherche d’une caméra ou webcam Windows…';
    });

    int cameraId = -1;

    try {
      final cameras = await CameraPlatform.instance.availableCameras().timeout(
        const Duration(seconds: 8),
      );

      if (cameras.isEmpty) {
        throw PlatformException(
          code: 'NoCamera',
          message: 'Aucune caméra Windows détectée.',
        );
      }

      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      cameraId = await CameraPlatform.instance
          .createCameraWithSettings(
            selectedCamera,
            const MediaSettings(
              resolutionPreset: ResolutionPreset.medium,
              fps: 15,
              videoBitrate: 200000,
              audioBitrate: 32000,
              enableAudio: false,
            ),
          )
          .timeout(const Duration(seconds: 8));

      _windowsErrorSubscription = CameraPlatform.instance
          .onCameraError(cameraId)
          .listen(_onWindowsCameraError);

      _windowsClosingSubscription = CameraPlatform.instance
          .onCameraClosing(cameraId)
          .listen(_onWindowsCameraClosing);

      final initializedEvent = CameraPlatform.instance
          .onCameraInitialized(cameraId)
          .first;

      await CameraPlatform.instance
          .initializeCamera(cameraId)
          .timeout(const Duration(seconds: 12));

      final event = await initializedEvent.timeout(const Duration(seconds: 12));

      if (!mounted || _isReturningResult) {
        try {
          await CameraPlatform.instance
              .dispose(cameraId)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
        return;
      }

      _windowsCameraId = cameraId;
      _windowsPreviewSize = Size(event.previewWidth, event.previewHeight);
      _windowsCameraStarted = true;

      setState(() {
        _windowsStatus = 'Caméra active. Présente le QR Code devant la webcam.';
      });

      _windowsScanTimer = Timer.periodic(
        const Duration(milliseconds: 1400),
        (_) => unawaited(_captureAndDecodeWindowsFrame()),
      );

      unawaited(_captureAndDecodeWindowsFrame());
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('Caméra Windows trop lente ou bloquée : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (cameraId >= 0) {
        try {
          await CameraPlatform.instance
              .dispose(cameraId)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }

      await _showWindowsCameraError(
        'La caméra Windows ne répond pas. Ferme les autres applications qui '
        'utilisent la webcam, puis réessaie.',
      );
    } on CameraException catch (error, stackTrace) {
      debugPrint(
        'Scanner QR Windows indisponible (${error.code}) : '
        '${error.description}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (cameraId >= 0) {
        try {
          await CameraPlatform.instance
              .dispose(cameraId)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }

      await _showWindowsCameraError(_windowsCameraMessage(error.code));
    } on PlatformException catch (error, stackTrace) {
      debugPrint(
        'Scanner QR Windows indisponible (${error.code}) : ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (cameraId >= 0) {
        try {
          await CameraPlatform.instance
              .dispose(cameraId)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }

      await _showWindowsCameraError(_windowsCameraMessage(error.code));
    } catch (error, stackTrace) {
      debugPrint('Scanner QR Windows indisponible : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (cameraId >= 0) {
        try {
          await CameraPlatform.instance
              .dispose(cameraId)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }

      await _showWindowsCameraError(
        'La caméra Windows n’a pas pu être ouverte. Vérifie les autorisations '
        'Caméra de Windows et ferme les applications qui utilisent la webcam.',
      );
    }
  }

  String _windowsCameraMessage(String code) {
    switch (code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Windows refuse l’accès à la caméra. Ouvre Paramètres Windows '
            '> Confidentialité et sécurité > Caméra, puis autorise la caméra '
            'pour les applications de bureau.';
      case 'NoCamera':
        return 'Aucune caméra ou webcam Windows n’a été détectée.';
      default:
        return 'La caméra Windows n’a pas pu être ouverte. Vérifie qu’elle '
            'n’est pas utilisée par une autre application et que Windows '
            'autorise son utilisation.';
    }
  }

  Future<void> _showWindowsCameraError(String message) async {
    await _disposeWindowsCamera();

    if (!mounted) {
      return;
    }

    setState(() {
      _windowsCameraUnavailable = true;
      _windowsStatus = message;
    });
  }

  void _onWindowsCameraError(CameraErrorEvent event) {
    debugPrint('Erreur caméra Windows : ${event.description}');

    if (!mounted || _isReturningResult) {
      return;
    }

    unawaited(
      _showWindowsCameraError(
        'La caméra Windows a rencontré une erreur. Vérifie qu’elle n’est pas '
        'utilisée par une autre application, puis réessaie.',
      ),
    );
  }

  void _onWindowsCameraClosing(CameraClosingEvent event) {
    debugPrint('Caméra Windows en cours de fermeture.');

    if (!mounted || _isReturningResult) {
      return;
    }

    _windowsScanTimer?.cancel();
    _windowsScanTimer = null;

    setState(() {
      _windowsCameraStarted = false;
      _windowsPreviewSize = null;
      _windowsStatus =
          'La caméra Windows a été fermée. Tu peux réessayer ou revenir à la '
          'sélection manuelle.';
      _windowsCameraUnavailable = true;
    });
  }

  Future<void> _captureAndDecodeWindowsFrame() async {
    final cameraId = _windowsCameraId;

    if (!_isWindows ||
        !_windowsCameraStarted ||
        cameraId < 0 ||
        _windowsCaptureRunning ||
        _isReturningResult) {
      return;
    }

    _windowsCaptureRunning = true;

    try {
      final picture = await CameraPlatform.instance
          .takePicture(cameraId)
          .timeout(const Duration(seconds: 5));

      final frame = await picture.readAsBytes();

      if (frame.isEmpty || _isReturningResult) {
        return;
      }

      final qrValue = _decodeWindowsQr(frame);

      if (qrValue == null || qrValue.isEmpty || _isReturningResult) {
        return;
      }

      _isReturningResult = true;
      _windowsScanTimer?.cancel();
      _windowsScanTimer = null;

      await _disposeWindowsCamera();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(qrValue);
    } on TimeoutException {
      debugPrint(
        'Capture webcam Windows trop longue : nouvelle tentative au prochain '
        'cycle.',
      );
    } on CameraException catch (error) {
      debugPrint(
        'Capture webcam Windows impossible (${error.code}) : '
        '${error.description}',
      );
    } catch (error) {
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

  Future<void> _disposeWindowsCamera() async {
    _windowsScanTimer?.cancel();
    _windowsScanTimer = null;

    unawaited(_windowsErrorSubscription?.cancel());
    _windowsErrorSubscription = null;

    unawaited(_windowsClosingSubscription?.cancel());
    _windowsClosingSubscription = null;

    final cameraId = _windowsCameraId;

    _windowsCameraId = -1;
    _windowsPreviewSize = null;
    _windowsCameraStarted = false;
    _windowsCaptureRunning = false;

    if (cameraId < 0) {
      return;
    }

    try {
      await CameraPlatform.instance
          .dispose(cameraId)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // La navigation ne doit jamais rester bloquée sur la fermeture caméra.
    }
  }

  @override
  void dispose() {
    _windowsScanTimer?.cancel();
    _windowsScanTimer = null;

    unawaited(_windowsErrorSubscription?.cancel());
    _windowsErrorSubscription = null;

    unawaited(_windowsClosingSubscription?.cancel());
    _windowsClosingSubscription = null;

    if (_isWindows) {
      final cameraId = _windowsCameraId;
      _windowsCameraId = -1;

      if (cameraId >= 0) {
        unawaited(CameraPlatform.instance.dispose(cameraId));
      }
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
    final cameraReady =
        _windowsCameraStarted &&
        _windowsCameraId >= 0 &&
        _windowsPreviewSize != null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cameraReady) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AspectRatio(
                        aspectRatio:
                            _windowsPreviewSize!.width /
                            _windowsPreviewSize!.height,
                        child: CameraPlatform.instance.buildPreview(
                          _windowsCameraId,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ] else
                    Icon(
                      _windowsCameraUnavailable
                          ? Icons.videocam_off_rounded
                          : Icons.qr_code_scanner_rounded,
                      size: 64,
                    ),
                  Text(
                    _windowsStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    cameraReady
                        ? 'Présente le QR Code devant la webcam. RC Companion '
                              'analyse automatiquement l’image.'
                        : 'RC Companion recherche une webcam utilisable sur '
                              'ce PC.',
                    textAlign: TextAlign.center,
                  ),
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
                      await _disposeWindowsCamera();

                      if (!context.mounted) {
                        return;
                      }

                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.keyboard_rounded),
                    label: const Text('Retour à la sélection manuelle'),
                  ),
                  if (_windowsCameraUnavailable) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Si la caméra reste indisponible, vérifie dans Windows '
                      'que l’accès Caméra est autorisé pour les applications '
                      'de bureau.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
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
