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
      _localBytes = null;
      _loadedLocalPath = null;
      _loadLocalPhoto();
    }
  }

  Future<void> _loadLocalPhoto() async {
    final path = widget.model.photoLocalPath?.trim() ?? '';

    if (path.isEmpty) {
      _localBytes = null;
      _loadedLocalPath = null;
      _isLoadingLocalPhoto = false;
      return;
    }

    if (_loadedLocalPath == path &&
        (_localBytes != null || _isLoadingLocalPhoto)) {
      return;
    }

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

    setState(() {
      _localBytes = bytes != null && bytes.isNotEmpty ? bytes : null;
      _isLoadingLocalPhoto = false;
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
