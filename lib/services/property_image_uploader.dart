import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// PropertyImageUploader — comprime imagen client-side (Dart puro, Web-safe)
/// y la sube al bucket `property-images` de Appwrite Storage. Retorna la URL
/// pública de visualización para guardar en `Property.photos[]`.
///
/// **Flow**:
///   1. Decode bytes → `Image` object.
///   2. Resize si el lado mayor > maxDim (default 1600px).
///   3. Re-encode JPEG con quality 78.
///   4. `Storage.createFile` con `ID.unique()`. El bucket tiene read=any y
///      fileSecurity=false → el archivo es público.
///   5. Construye la URL de view:
///      `<endpoint>/storage/buckets/<bucket>/files/<fileId>/view?project=<projectId>`.
///
/// **Web safe**: el package `image` corre en Dart puro (idéntico en
/// Web/Mobile/Desktop). ~3-5× más lento que un encoder nativo, pero para
/// uploads únicos a 1600px es aceptable (<2s).
class PropertyImageUploader {
  final Storage _storage;
  final String _endpoint;
  final String _projectId;
  final String bucket;

  PropertyImageUploader({
    required Storage storage,
    required String endpoint,
    required String projectId,
    this.bucket = 'property-images',
  })  : _storage = storage,
        _endpoint = endpoint.replaceAll(RegExp(r'/+$'), ''),
        _projectId = projectId;

  /// Compresión + upload. Retorna URL pública (rethrow si falla).
  ///
  /// - [bytes]: bytes raw del archivo seleccionado.
  /// - [propertyId]: usado para nombrar el archivo (e.g. `agent-XXX-ts.jpg`).
  /// - [maxDimension]: lado mayor objetivo en px. Default 1600.
  /// - [quality]: 0-100 para encoder JPEG. Default 78.
  Future<String> compressAndUpload({
    required Uint8List bytes,
    required String propertyId,
    int maxDimension = 1600,
    int quality = 78,
  }) async {
    final compressed = await _compress(
      bytes: bytes,
      maxDimension: maxDimension,
      quality: quality,
    );
    debugPrint(
      '[Hito.ImgUpload] compress ${bytes.length} → ${compressed.length} bytes '
      '(${(compressed.length * 100 / bytes.length).toStringAsFixed(0)}%)',
    );

    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = '$propertyId-$ts.jpg';

    try {
      final created = await _storage.createFile(
        bucketId: bucket,
        fileId: ID.unique(),
        file: InputFile.fromBytes(
          bytes: compressed,
          filename: fileName,
          contentType: 'image/jpeg',
        ),
      );
      final url = '$_endpoint/storage/buckets/$bucket/files/'
          '${created.$id}/view?project=$_projectId';
      debugPrint('[Hito.ImgUpload] uploaded → $url');
      return url;
    } catch (e) {
      debugPrint('[Hito.ImgUpload] upload failed: $e');
      rethrow;
    }
  }

  /// Compresión pura — ejecuta el work en compute() para no bloquear la
  /// UI thread con un decode+resize+encode pesado.
  Future<Uint8List> _compress({
    required Uint8List bytes,
    required int maxDimension,
    required int quality,
  }) async {
    return compute(_compressIsolate, _CompressJob(
      bytes: bytes,
      maxDimension: maxDimension,
      quality: quality,
    ));
  }
}

class _CompressJob {
  final Uint8List bytes;
  final int maxDimension;
  final int quality;
  _CompressJob({
    required this.bytes,
    required this.maxDimension,
    required this.quality,
  });
}

Uint8List _compressIsolate(_CompressJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) {
    throw FormatException(
      'No se pudo decodificar la imagen. Formato no soportado o archivo corrupto.',
    );
  }
  var image = decoded;
  final longSide = image.width > image.height ? image.width : image.height;
  if (longSide > job.maxDimension) {
    final scale = job.maxDimension / longSide;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: job.quality));
}
