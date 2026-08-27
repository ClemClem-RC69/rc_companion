import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/rc_model.dart';
import '../../services/model_photo_file_store.dart';

class ModelPhotoWidget extends StatefulWidget {
  const ModelPhotoWidget({
    super.key,
    required this.model,
    required this.fallback,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
  });

  final RcModel model;
  final Widget fallback;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  State<ModelPhotoWidget> createState() => _ModelPhotoWidgetState();
}

class _ModelPhotoWidgetState extends State<ModelPhotoWidget> {
  Uint8List? _localBytes;
  String? _loadedLocalPath;
  bool _isLoadingLocalPhoto = false;
  Timer? _retryTimer;
  int _retryCount = 0;

  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 60),
    Duration(milliseconds: 180),
    Duration(milliseconds: 450),
  ];

  @override
  void initState() {
    super.initState();
    _loadLocalPhoto();
  }

  @override
  void didUpdateWidget(covariant ModelPhotoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldPath = oldWidget.model.photoLocalPath?.trim() ?? '';
    final newPath = widget.model.photoLocalPath?.trim() ?? '';

    if (oldPath != newPath) {
      _resetLocalPhotoState();
      _loadLocalPhoto();
      return;
    }

    // Si une première lecture locale a échoué pendant une reconstruction
    // ou une mise à jour Drift, on ne reste jamais bloqué sur le fallback.
    if (newPath.isNotEmpty &&
        _localBytes == null &&
        !_isLoadingLocalPhoto &&
        _retryTimer == null) {
      _retryCount = 0;
      _loadLocalPhoto(force: true);
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _resetLocalPhotoState() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryCount = 0;
    _localBytes = null;
    _loadedLocalPath = null;
    _isLoadingLocalPhoto = false;
  }

  Future<void> _loadLocalPhoto({bool force = false}) async {
    final path = widget.model.photoLocalPath?.trim() ?? '';

    if (path.isEmpty) {
      _resetLocalPhotoState();
      return;
    }

    if (!force &&
        _loadedLocalPath == path &&
        (_localBytes != null || _isLoadingLocalPhoto)) {
      return;
    }

    _retryTimer?.cancel();
    _retryTimer = null;
    _loadedLocalPath = path;
    _isLoadingLocalPhoto = true;

    final bytes = await ModelPhotoFileStore.readBytes(path);

    if (!mounted) {
      return;
    }

    final currentPath = widget.model.photoLocalPath?.trim() ?? '';
    if (currentPath != path) {
      return;
    }

    if (bytes != null && bytes.isNotEmpty) {
      setState(() {
        _localBytes = bytes;
        _isLoadingLocalPhoto = false;
        _retryCount = 0;
      });
      return;
    }

    setState(() {
      _localBytes = null;
      _isLoadingLocalPhoto = false;
    });

    _scheduleRetry(path);
  }

  void _scheduleRetry(String path) {
    if (!mounted || _retryCount >= _retryDelays.length) {
      return;
    }

    final delay = _retryDelays[_retryCount];
    _retryCount += 1;

    _retryTimer = Timer(delay, () {
      _retryTimer = null;

      if (!mounted) {
        return;
      }

      final currentPath = widget.model.photoLocalPath?.trim() ?? '';
      if (currentPath != path || currentPath.isEmpty) {
        return;
      }

      _loadLocalPhoto(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _localBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
      );
    }

    return _remoteOrFallback();
  }

  Widget _remoteOrFallback() {
    final url = widget.model.photoUrl;
    if (url == null || url.trim().isEmpty || url.trim().startsWith('gdrive:')) {
      return widget.fallback;
    }

    return Image.network(
      url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => widget.fallback,
    );
  }
}
