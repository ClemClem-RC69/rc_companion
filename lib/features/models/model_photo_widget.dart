import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/rc_model.dart';
import '../../services/model_photo_file_store.dart';

class ModelPhotoWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final localPath = model.photoLocalPath;
    if (localPath != null && localPath.trim().isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: ModelPhotoFileStore.readBytes(localPath),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(
              bytes,
              width: width,
              height: height,
              fit: fit,
              gaplessPlayback: true,
            );
          }
          return _remoteOrFallback();
        },
      );
    }
    return _remoteOrFallback();
  }

  Widget _remoteOrFallback() {
    final url = model.photoUrl;
    if (url == null || url.trim().isEmpty) return fallback;
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
