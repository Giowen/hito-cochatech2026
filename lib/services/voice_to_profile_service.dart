import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/client_profile.dart';
import '../utils/landmarks.dart';
import '../utils/tc_paralelo.dart';
import 'groq_client.dart';

/// Pipeline voz → texto → perfil estructurado.
///
/// Flow:
///   1. `audioFromUrl(blobOrFileUrl)` lee los bytes del audio (Web: blob,
///      mobile: file://).
///   2. `transcribe(bytes)` llama Groq Whisper API y devuelve texto.
///   3. `extractProfile(transcript)` llama Groq Llama 3.3 con prompt español
///      boliviano, parsea JSON y construye un ClientProfile usable por el
///      MatchingService (coords resueltas desde Landmarks).
///
/// Cero pieza hardcodeada — todo viene del LLM con el texto real del usuario.
class VoiceToProfileService {
  final GroqClient _groq;
  final Dio _dio;

  VoiceToProfileService({GroqClient? groq, Dio? dio})
      : _groq = groq ?? GroqClient(),
        _dio = dio ?? Dio();

  /// Lee bytes de una URL (blob:// en Web, file:// o path en mobile).
  /// Usa Dio para abstraer plataforma.
  Future<Uint8List> audioFromUrl(String url) async {
    debugPrint('[Hito.Voice] fetching audio bytes from: $url');
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  /// Transcribe los bytes de audio. Auto-detecta filename por plataforma
  /// (webm en browser, m4a en mobile/desktop).
  Future<String> transcribe(Uint8List bytes) async {
    final filename = kIsWeb ? 'audio.webm' : 'audio.m4a';
    debugPrint(
      '[Hito.Voice] Whisper transcribe ${bytes.length} bytes ($filename)',
    );
    final text = await _groq.transcribe(
      audioBytes: bytes,
      filename: filename,
    );
    debugPrint('[Hito.Voice] transcript: "$text"');
    return text;
  }

  static const _extractionSystemPrompt = '''
Eres un parser de búsquedas inmobiliarias en Oruro, Bolivia. El usuario
describió en lenguaje natural lo que busca. Convierte a JSON estructurado.

INTERPRETACIÓN DE PRESUPUESTO (regla crítica):
- "120k", "120 mil", "ciento veinte mil", "120000" → asume USD por DEFAULT.
- Solo si menciona explícitamente "bolivianos", "Bs", "BOB" → es BOB.
  Convertir con TC paralelo 10.20: "300 mil bolivianos" → \$24590 USD.
- "k" = mil. "M" = millón. "120k" = 120000.
- En Oruro 2026 propiedades familiares cuestan típicamente \$50k-\$160k USD.
  Si el número extraído es <\$15k USD, casi seguro el usuario habló en BOB.
  Si es >\$1M USD, casi seguro habló en BOB. Validá rangos sanos.

LANDMARKS válidos para "desired_landmark":
- uto, fni, ucb (universidades)
- centro (Plaza 10 de Febrero), mercado (zona comercial), hospital (servicios)
- socavon, faro, estadio (hitos de la ciudad)
- la_floresta, agua_de_castilla, norte, sud, este, san_jose,
  villa_esperanza, las_kantutas, sebastian_pagador, challacollo (barrios)
- aeropuerto (Juan Mendoza), terminal (terminal de buses)

Si el usuario menciona una zona/barrio que NO está en esta lista, devuelve
el slug normalizado en minúsculas con guiones bajos (ej. "barrio_nuevo")
— el sistema intentará geocodificarlo automáticamente.

TAGS válidos para "required_tags":
- patio, jardin, garage, cochera, vigilancia, piscina, terraza, balcon
- familia_segura, mascotas_aceptadas, zona_tranquila
- cerca_universidad, cerca_oficina, cerca_centro, cerca_recoleta
- vista_panoramica, quincho, acepta_anticretico

REGLAS:
- Si menciona "familia", "hijos", "esposa", "niños" → agrega "familia_segura"
- Modalidad (transaction_type) — REGLAS ESTRICTAS:
  * "alquiler" SÓLO si menciona explícito "alquilar", "alquiler", "arrendar",
    "rentar", "renta mensual". NO infieras alquiler del monto del presupuesto.
  * "anticretico" si menciona "anticrético" o "anticretico".
  * "compra" en TODOS los demás casos (default seguro).
  * Si dice solo "tengo 25 mil" sin modalidad → compra (NO alquiler).
- Si menciona "anticrético" como interés secundario (no modalidad principal),
  pon transaction_type según la modalidad principal Y agrega "acepta_anticretico"
  a required_tags.
- Si dice "cerca de UMSS" o "cerca de la universidad" → desired_landmark = "umss"
- Si menciona "oficina en Recoleta" o similar → desired_landmark = "recoleta"
- min_area_m2 default 80 si no se menciona
- budget_min_usd default = (budget_max_usd * 0.6).round()
- desired_landmark — REGLAS ESTRICTAS:
  * Si user NO menciona zona, barrio, landmark, universidad, oficina, ni
    expresión de proximidad ("cerca de X") → desired_landmark = null
  * Si user menciona solo "departamento" o "casa" sin lugar → null
  * SOLO cuando user dice "cerca de UMSS", "en Cala Cala", "por Recoleta",
    "en el centro", etc → pon el slug correspondiente
- max_distance_km_to_landmark:
  * Si desired_landmark NO es null → 2.0 (default cerca)
  * Si desired_landmark es null → 999 (sin restricción geográfica)

OUTPUT JSON estricto (sin markdown, solo el objeto):
{
  "budget_max_usd": int,
  "budget_min_usd": int,
  "transaction_type": "compra" | "alquiler" | "anticretico",
  "min_bedrooms": int,
  "min_area_m2": int,
  "required_tags": [strings],
  "desired_landmark": string | null,
  "max_distance_km_to_landmark": number
}
''';

  /// Llama Groq Llama 3.3 para extraer un ClientProfile estructurado del
  /// texto del usuario. Resuelve `desired_landmark` a coords usando Landmarks.
  Future<ClientProfile> extractProfile(String transcript) async {
    if (transcript.trim().isEmpty) {
      throw ArgumentError('Empty transcript');
    }

    debugPrint('[Hito.Voice] extracting profile from transcript via Groq');
    final raw = await _groq.chat(
      messages: [
        const {'role': 'system', 'content': _extractionSystemPrompt},
        {'role': 'user', 'content': transcript},
      ],
      model: GroqModels.voiceExtract,
      temperature: 0.1,
      responseFormat: {'type': 'json_object'},
    );

    final json = GroqClient.extractJson(raw);
    if (json == null) {
      throw FormatException('Groq returned non-JSON profile: $raw');
    }

    return await _jsonToProfile(json, transcript);
  }

  Future<ClientProfile> _jsonToProfile(
    Map<String, dynamic> json,
    String transcript,
  ) async {
    final budgetMaxUsd =
        (json['budget_max_usd'] as num?)?.toInt() ?? 200000;
    final budgetMinUsd = (json['budget_min_usd'] as num?)?.toInt() ??
        (budgetMaxUsd * 0.6).round();

    final transactionType =
        (json['transaction_type'] as String?) ?? 'compra';
    final minBedrooms = (json['min_bedrooms'] as num?)?.toInt() ?? 2;
    final minAreaM2 = (json['min_area_m2'] as num?)?.toInt() ?? 80;
    final requiredTags =
        ((json['required_tags'] as List?) ?? const []).cast<String>();
    final landmarkSlug = json['desired_landmark'] as String?;
    final hasLandmark = landmarkSlug != null && landmarkSlug.isNotEmpty;
    final rawRadius =
        (json['max_distance_km_to_landmark'] as num?)?.toDouble() ?? 999.0;
    // Si no hay landmark → radius sentinel 999 (sin restricción geográfica).
    final radiusKm = hasLandmark ? rawRadius : 999.0;

    // Resolver coords: primero del catálogo, luego Nominatim, luego centro.
    LatLng? coords;
    String resolvedLandmark = landmarkSlug ?? 'centro';
    if (landmarkSlug != null && landmarkSlug.isNotEmpty) {
      final fromCatalog = Landmarks.bySlug[landmarkSlug];
      if (fromCatalog != null) {
        coords = fromCatalog.coords;
      } else {
        // Fallback: Nominatim geocode para zonas no catalogadas
        coords = await _geocodeLandmark(landmarkSlug);
        if (coords != null) {
          resolvedLandmark = '$landmarkSlug (geocoded)';
        }
      }
    }
    coords ??= Landmarks.centroPlazaPrincipal.coords;

    debugPrint(
      '[Hito.Voice] extracted: budget=$budgetMinUsd-$budgetMaxUsd USD '
      'type=$transactionType bd=$minBedrooms area=$minAreaM2 '
      'landmark=$resolvedLandmark coords=${coords.latitude.toStringAsFixed(3)},${coords.longitude.toStringAsFixed(3)} '
      'radius=$radiusKm',
    );

    return ClientProfile(
      id: 'voice-${DateTime.now().millisecondsSinceEpoch}',
      budgetMin: TcParalelo.usdToBob(budgetMinUsd),
      budgetMax: TcParalelo.usdToBob(budgetMaxUsd),
      transactionType: transactionType,
      desiredLat: coords.latitude,
      desiredLng: coords.longitude,
      radiusKm: radiusKm,
      minBedrooms: minBedrooms,
      minAreaM2: minAreaM2,
      requiredTags: requiredTags,
      voiceInputTranscript: transcript,
    );
  }

  /// Geocodifica un nombre de zona vía OSM Nominatim cuando no está en el
  /// catálogo Landmarks. Restringe búsqueda a Bolivia.
  Future<LatLng?> _geocodeLandmark(String slug) async {
    try {
      final query = '${slug.replaceAll('_', ' ')}, Oruro, Bolivia';
      debugPrint('[Hito.Voice] geocoding unknown landmark: "$query"');
      final response = await _dio.get<String>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'jsonv2',
          'limit': '1',
          'countrycodes': 'bo',
        },
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s >= 200 && s < 500,
        ),
      );
      if (response.statusCode != 200) return null;
      final raw = response.data;
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first as Map<String, dynamic>;
      final lat = double.parse(first['lat'].toString());
      final lng = double.parse(first['lon'].toString());
      return LatLng(lat, lng);
    } catch (e) {
      debugPrint('[Hito.Voice] landmark geocode failed: $e');
      return null;
    }
  }

  /// Pipeline completo: bytes audio → ClientProfile listo para matching.
  Future<({String transcript, ClientProfile profile})> voiceToProfile(
    Uint8List bytes,
  ) async {
    final transcript = await transcribe(bytes);
    if (transcript.isEmpty) {
      throw StateError('Whisper devolvió transcript vacío');
    }
    final profile = await extractProfile(transcript);
    return (transcript: transcript, profile: profile);
  }
}
