import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// The self-hosted image store: original photos are copied into the app's
/// private storage on the device and never uploaded anywhere for storage.
class ImageVault {
  final Directory root;

  ImageVault(this.root);

  /// Longest edge sent to the AI. Larger images are downscaled server-side
  /// anyway, so sending more only costs upload time and tokens.
  static const int aiMaxEdge = 1568;

  File fileFor(String fileName) => File(p.join(root.path, fileName));

  /// Copies [source] into the vault under [fileName] and returns it.
  Future<File> import(File source, String fileName) async {
    await root.create(recursive: true);
    return source.copy(fileFor(fileName).path);
  }

  Future<void> remove(String fileName) async {
    final file = fileFor(fileName);
    if (await file.exists()) await file.delete();
  }

  /// Returns a JPEG of the vault image, downscaled for the AI request.
  /// Decoding runs in a background isolate to keep the UI smooth.
  Future<Uint8List> jpegForAi(String fileName) async {
    final bytes = await fileFor(fileName).readAsBytes();
    return compute(downscaleToJpeg, bytes);
  }
}

/// Decodes any supported format, applies EXIF orientation, shrinks the
/// longest edge to [ImageVault.aiMaxEdge] and re-encodes as JPEG.
Uint8List downscaleToJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported or corrupt image file.');
  }
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > ImageVault.aiMaxEdge) {
    image = image.width >= image.height
        ? img.copyResize(image, width: ImageVault.aiMaxEdge)
        : img.copyResize(image, height: ImageVault.aiMaxEdge);
  }
  return img.encodeJpg(image, quality: 85);
}
