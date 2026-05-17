import 'package:flutter/foundation.dart';

import '../utils/env.dart';

/// AssetStorage — interface para upload de assets binarios (fotos, PDFs, audio).
///
/// **Por qué Cloudflare R2 (vs S3, Firebase Storage, Supabase Storage)**:
///   - Egress: **\$0** (S3 cobra \$0.09/GB, Firebase \$0.12/GB)
///   - Storage: **\$0.015/GB/mo** (S3 \$0.023, Firebase \$0.026)
///   - S3-compatible API → cualquier SDK S3 funciona sin cambios
///   - CDN incluido vía Cloudflare edge network sin paywall extra
///   - Bolivia → Cloudflare PoP en São Paulo: ~25ms latency
///
/// Para 10K agentes × 50MB fotos cada uno = 500GB total = \$7.50/mo storage.
/// Egress libre = clientes finales descargan fotos gratis sin facturar.
///
/// **MVP (hackathon)**: `MockAssetStorage` retorna placeholder URLs.
/// **Phase 2 (post-pitch)**: `R2AssetStorage` real vía minio_dart o aws_client.
abstract class AssetStorage {
  /// Upload foto de propiedad. Retorna URL pública servida vía Cloudflare CDN.
  Future<String> uploadPropertyPhoto({
    required String propertyId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  });

  /// Upload contrato (PDF) para análisis legal.
  /// Returned URL alimenta `contract_analysis_service.loadFromUrl(url)`.
  Future<String> uploadContract({
    required String contractId,
    required Uint8List bytes,
    String contentType = 'application/pdf',
  });

  /// Upload audio recording. Returned URL alimenta Groq Whisper API
  /// (que acepta URL pública o multipart upload). En producción Whisper se
  /// invoca server-side vía Cloudflare Worker que recibe el R2 URL.
  Future<String> uploadVoiceRecording({
    required String sessionId,
    required Uint8List bytes,
    String contentType = 'audio/m4a',
  });

  /// Eliminar asset por URL/key.
  Future<void> delete(String url);
}

/// MockAssetStorage — implementación MVP que NO sube nada real.
/// Genera URLs determinísticas que apuntan a placeholder/seed assets.
///
/// Útil para demo: jurado no upload assets durante el pitch de 3 min.
/// Para QA post-pitch funcional con uploads reales → wire R2AssetStorage.
class MockAssetStorage implements AssetStorage {
  static const _baseUrl = 'https://hito-assets.r2.dev';

  @override
  Future<String> uploadPropertyPhoto({
    required String propertyId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    await Future.delayed(const Duration(milliseconds: 240)); // simula network
    debugPrint(
      '[Hito.MockAssetStorage] uploadPropertyPhoto: '
      'propertyId=$propertyId bytes=${bytes.length} type=$contentType',
    );
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$_baseUrl/photos/$propertyId-$ts.jpg';
  }

  @override
  Future<String> uploadContract({
    required String contractId,
    required Uint8List bytes,
    String contentType = 'application/pdf',
  }) async {
    await Future.delayed(const Duration(milliseconds: 320));
    debugPrint(
      '[Hito.MockAssetStorage] uploadContract: '
      'contractId=$contractId bytes=${bytes.length}',
    );
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$_baseUrl/contracts/$contractId-$ts.pdf';
  }

  @override
  Future<String> uploadVoiceRecording({
    required String sessionId,
    required Uint8List bytes,
    String contentType = 'audio/m4a',
  }) async {
    await Future.delayed(const Duration(milliseconds: 180));
    debugPrint(
      '[Hito.MockAssetStorage] uploadVoiceRecording: '
      'sessionId=$sessionId bytes=${bytes.length}',
    );
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$_baseUrl/voice/$sessionId-$ts.m4a';
  }

  @override
  Future<void> delete(String url) async {
    debugPrint('[Hito.MockAssetStorage] delete: $url (no-op)');
  }
}

/// R2AssetStorage — implementación real con Cloudflare R2 (S3-compatible).
///
/// **Setup requerido en producción** (Phase 2):
///   1. Cloudflare dashboard → R2 → Create bucket "hito-assets"
///   2. R2 → Manage R2 API Tokens → Create token "hito-flutter"
///      Permissions: Object Read & Write para bucket hito-assets
///   3. Copy Access Key ID + Secret Access Key + Endpoint URL
///   4. Agregar a .env:
///      `R2_ACCOUNT_ID=ACCOUNT_ID`
///      `R2_BUCKET=hito-assets`
///      `R2_ACCESS_KEY_ID=KEY`
///      `R2_SECRET_ACCESS_KEY=SECRET`
///      `R2_PUBLIC_BASE_URL=https://pub-HASH.r2.dev`   (or custom domain)
///   5. `flutter pub add minio` (S3-compatible client) o `aws_client`
///   6. Implementar upload methods abajo
///
/// **Seguridad**: en producción, NO embeber Access Key en cliente Flutter.
/// Pattern correcto: Cloudflare Worker como proxy que firma presigned URLs;
/// el cliente Flutter sube directamente a R2 vía esa signed URL temporal.
/// Eso es Phase 2 work — minio_dart funciona ahí mismo.
///
/// Por ahora esta clase está SCAFFOLDED (no implementada) — el switch en
/// `assetStorageProvider` se hace cuando minio_dart está agregado al pubspec.
class R2AssetStorage implements AssetStorage {
  final String accountId;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
  final String publicBaseUrl;

  R2AssetStorage({
    required this.accountId,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.publicBaseUrl,
  });

  /// Construye desde env (compile-time defines o .env). Lanza StateError si
  /// falta alguna variable.
  factory R2AssetStorage.fromEnv() {
    final accountId = Env.get('R2_ACCOUNT_ID');
    final bucket = Env.get('R2_BUCKET');
    final accessKey = Env.get('R2_ACCESS_KEY_ID');
    final secret = Env.get('R2_SECRET_ACCESS_KEY');
    final publicUrl = Env.get('R2_PUBLIC_BASE_URL');
    if (accountId == null ||
        bucket == null ||
        accessKey == null ||
        secret == null ||
        publicUrl == null) {
      throw StateError(
        'R2 credentials missing. Pass via --dart-define=R2_ACCOUNT_ID=... etc, '
        'or include in local .env. Requires R2_ACCOUNT_ID, R2_BUCKET, '
        'R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_PUBLIC_BASE_URL. '
        'See ARCHITECTURE.md.',
      );
    }
    return R2AssetStorage(
      accountId: accountId,
      bucket: bucket,
      accessKeyId: accessKey,
      secretAccessKey: secret,
      publicBaseUrl: publicUrl,
    );
  }

  /// S3-compatible endpoint para esta cuenta de R2.
  /// `https://{account_id}.r2.cloudflarestorage.com`
  String get endpoint => 'https://$accountId.r2.cloudflarestorage.com';

  @override
  Future<String> uploadPropertyPhoto({
    required String propertyId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    // TODO Phase 2: implementar con minio_dart o aws_client.
    // Pseudo-código de la implementación final:
    //
    //   final minio = Minio(
    //     endPoint: '$accountId.r2.cloudflarestorage.com',
    //     accessKey: accessKeyId,
    //     secretKey: secretAccessKey,
    //     useSSL: true,
    //   );
    //   final key = 'photos/$propertyId-${DateTime.now().millisecondsSinceEpoch}.jpg';
    //   await minio.putObject(bucket, key, Stream.fromIterable([bytes]),
    //     size: bytes.length, metadata: {'Content-Type': contentType});
    //   return '$publicBaseUrl/$key';
    throw UnimplementedError(
      'R2 upload no implementado en MVP. Usa MockAssetStorage o agrega '
      'minio_dart al pubspec y descomenta el código de arriba.',
    );
  }

  @override
  Future<String> uploadContract({
    required String contractId,
    required Uint8List bytes,
    String contentType = 'application/pdf',
  }) async {
    // TODO Phase 2: same pattern as uploadPropertyPhoto.
    throw UnimplementedError('R2 upload no implementado en MVP.');
  }

  @override
  Future<String> uploadVoiceRecording({
    required String sessionId,
    required Uint8List bytes,
    String contentType = 'audio/m4a',
  }) async {
    // TODO Phase 2: same pattern as uploadPropertyPhoto.
    throw UnimplementedError('R2 upload no implementado en MVP.');
  }

  @override
  Future<void> delete(String url) async {
    // TODO Phase 2: minio.removeObject(bucket, keyFromUrl(url))
    throw UnimplementedError('R2 delete no implementado en MVP.');
  }
}
