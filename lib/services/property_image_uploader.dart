import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

/// PropertyImageUploader — comprime imagen client-side (Dart puro, Web-safe)
/// y la sube al bucket `property-images` de Supabase Storage. Retorna la URL
/// pública para guardar en `Property.photos[]`.
///
/// **Flow**:
///   1. Decode bytes → `Image` object.
///   2. Resize si el lado mayor > maxDim (default 1600px) para que no se
///      suba un teléfono moderno con foto 4K de 8MB cuando 1600px ya es
///      suficiente para listing inmobiliario.
///   3. Re-encode JPEG con quality 78 (sweet spot calidad/peso).
///   4. PUT a `/storage/v1/object/property-images/{propertyId}-{ts}.jpg`
///      con upsert headers para que re-subida sobrescriba.
///   5. Construye URL pública: `<supabase>/storage/v1/object/public/<bucket>/<filename>`.
///
/// **Web safe**: a diferencia de `flutter_image_compress` (que requiere
/// código nativo Android/iOS), el package `image` corre en Dart puro y
/// funciona idéntico en Web/Mobile/Desktop. El trade-off es que es ~3-5×
/// más lento que un encoder nativo, pero para uploads únicos a 1600px es
/// totalmente aceptable (<2s).
class PropertyImageUploader {
  final SupabaseClient _client;
  final String bucket;

  PropertyImageUploader({
    SupabaseClient? client,
    this.bucket = 'property-images',
  }) : _client = client ?? Supabase.instance.client;

  /// Compresión + upload. Retorna URL pública (vacío si falla).
  ///
  /// - [bytes]: bytes raw del archivo seleccionado.
  /// - [propertyId]: usado para nombrar el archivo (e.g. `agent-XXX-ts.jpg`).
  /// - [maxDimension]: lado mayor objetivo en px. Default 1600 — equilibrio
  ///   entre calidad mostrable y peso de upload.
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
      await _client.storage.from(bucket).uploadBinary(
            fileName,
            compressed,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      final url = _client.storage.from(bucket).getPublicUrl(fileName);
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
    // En Web `compute` corre en el isolate principal igual (no hay isolates
    // verdaderos); aún así reduce el lag al permitir microtasks intercalados.
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
