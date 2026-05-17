import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Modelos asignados por tarea. Los IDs se resuelven dinámicamente según el
/// provider activo (OpenRouter si `OPENROUTER_API_KEY` presente, Groq si no).
///
/// **Decisión arquitectónica**: Whisper (transcribe) SIEMPRE va a Groq —
/// OpenRouter no expone audio endpoints. Los chats (matching/valuation/
/// contract/voice-extract) van a OpenRouter cuando está configurado, para
/// evitar rate limits del free tier de Groq.
class GroqModels {
  static bool get _isOpenRouter {
    final key = dotenv.env['OPENROUTER_API_KEY'];
    return key != null && key.isNotEmpty;
  }

  static String _resolve({
    required String groq,
    required String openrouter,
  }) =>
      _isOpenRouter ? openrouter : groq;

  /// Matching primary — Llama 3.3 70B con quality alta.
  /// En Groq: 1K RPD; en OpenRouter: pay-as-you-go sin límite.
  static String get matchingPrimary => _resolve(
        groq: 'llama-3.3-70b-versatile',
        openrouter: 'meta-llama/llama-3.3-70b-instruct',
      );

  /// Matching fallback — Llama 3.1 8B, más rápido pero menos quality.
  /// Solo usado en Groq cuando 70b hits rate limit. En OpenRouter no hace
  /// fallback porque no hay rate limit relevante.
  static String get matchingFallback => _resolve(
        groq: 'llama-3.1-8b-instant',
        openrouter: 'meta-llama/llama-3.1-8b-instruct',
      );

  /// Valuación: 1 call por property, requiere razonamiento profundo.
  static String get valuation => _resolve(
        groq: 'llama-3.3-70b-versatile',
        openrouter: 'meta-llama/llama-3.3-70b-instruct',
      );

  /// Análisis de contrato: 1 call, requiere conocimiento legal.
  static String get contract => _resolve(
        groq: 'llama-3.3-70b-versatile',
        openrouter: 'meta-llama/llama-3.3-70b-instruct',
      );

  /// Generación de borrador de contrato: 1 call, plantilla creativa.
  static String get contractGenerate => _resolve(
        groq: 'llama-3.3-70b-versatile',
        openrouter: 'meta-llama/llama-3.3-70b-instruct',
      );

  /// Voz → ClientProfile JSON: 1 call, parsing estructurado.
  static String get voiceExtract => _resolve(
        groq: 'llama-3.3-70b-versatile',
        openrouter: 'meta-llama/llama-3.3-70b-instruct',
      );

  /// Speech-to-text — SIEMPRE Groq (OpenRouter no expone audio).
  static const whisper = 'whisper-large-v3-turbo';

  /// Provider activo, para logging/debug.
  static String get activeProvider => _isOpenRouter ? 'openrouter' : 'groq';
}

/// Cliente unificado para LLM APIs OpenAI-compatible.
/// Auto-rutea chat/chatStream a OpenRouter si OPENROUTER_API_KEY está en .env;
/// caso contrario usa GROQ_API_KEY. Whisper transcribe siempre va a Groq.
class GroqClient {
  final Dio _dio;
  static const String _groqBaseUrl = 'https://api.groq.com/openai/v1';
  static const String _openrouterBaseUrl = 'https://openrouter.ai/api/v1';

  GroqClient({Dio? dio}) : _dio = dio ?? Dio();

  /// Detecta provider activo basado en env. OpenRouter tiene precedencia
  /// si OPENROUTER_API_KEY está presente y no vacía.
  bool get _isOpenRouter {
    final key = dotenv.env['OPENROUTER_API_KEY'];
    return key != null && key.isNotEmpty;
  }

  /// API key para chat — OpenRouter si configurado, Groq como fallback.
  String? get _chatApiKey {
    if (_isOpenRouter) {
      final key = dotenv.env['OPENROUTER_API_KEY'];
      if (key != null && key.isNotEmpty) return key;
    }
    final groqKey = dotenv.env['GROQ_API_KEY'];
    if (groqKey == null || groqKey.isEmpty) return null;
    return groqKey;
  }

  /// API key para Whisper — SIEMPRE Groq.
  String? get _whisperApiKey {
    final key = dotenv.env['GROQ_API_KEY'];
    if (key == null || key.isEmpty) return null;
    return key;
  }

  /// Base URL para chat según provider.
  String get _chatBaseUrl =>
      _isOpenRouter ? _openrouterBaseUrl : _groqBaseUrl;

  /// Headers comunes para chat — OpenRouter pide HTTP-Referer + X-Title
  /// para analytics (no obligatorio pero recomendado).
  Map<String, String> _chatHeaders(String apiKey) {
    final headers = <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    if (_isOpenRouter) {
      headers['HTTP-Referer'] = 'https://hito.cochatech.bo';
      headers['X-Title'] = 'Hito · Inteligencia Inmobiliaria';
    }
    return headers;
  }

  /// Chat completion non-streaming. Retorna el texto completo de la respuesta.
  Future<String> chat({
    required List<Map<String, String>> messages,
    String? model,
    double temperature = 0.3,
    Map<String, dynamic>? responseFormat,
  }) async {
    final apiKey = _chatApiKey;
    if (apiKey == null) {
      throw Exception(
        'No API key — set OPENROUTER_API_KEY or GROQ_API_KEY in .env',
      );
    }
    final effectiveModel = model ?? GroqModels.matchingPrimary;

    final body = <String, dynamic>{
      'model': effectiveModel,
      'messages': messages,
      'temperature': temperature,
    };
    if (responseFormat != null) {
      body['response_format'] = responseFormat;
    }

    if (kDebugMode) {
      debugPrint(
        '[Hito.LlmClient] chat via ${_isOpenRouter ? "OpenRouter" : "Groq"} '
        'model=$effectiveModel',
      );
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_chatBaseUrl/chat/completions',
        data: body,
        options: Options(headers: _chatHeaders(apiKey)),
      );
      final content =
          response.data!['choices'][0]['message']['content'] as String;
      return content;
    } on DioException catch (e) {
      // Log response body on 4xx para diagnosticar (key inválida, modelo
      // no disponible, deposit faltante, etc).
      if (e.response != null) {
        debugPrint(
          '[Hito.LlmClient] ${_isOpenRouter ? "OpenRouter" : "Groq"} '
          'HTTP ${e.response?.statusCode} body: ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// Chat completion streaming. Yields deltas de contenido token-by-token.
  Stream<String> chatStream({
    required List<Map<String, String>> messages,
    String? model,
    double temperature = 0.3,
  }) async* {
    final apiKey = _chatApiKey;
    if (apiKey == null) {
      throw Exception(
        'No API key — set OPENROUTER_API_KEY or GROQ_API_KEY in .env',
      );
    }
    final effectiveModel = model ?? GroqModels.matchingPrimary;

    final response = await _dio.post<ResponseBody>(
      '$_chatBaseUrl/chat/completions',
      data: {
        'model': effectiveModel,
        'messages': messages,
        'temperature': temperature,
        'stream': true,
      },
      options: Options(
        headers: _chatHeaders(apiKey),
        responseType: ResponseType.stream,
      ),
    );

    await for (final chunk in response.data!.stream) {
      final text = utf8.decode(chunk, allowMalformed: true);
      for (final line in text.split('\n')) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') continue;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final delta = (json['choices'] as List?)?[0]?['delta']
                ?['content'] as String?;
            if (delta != null && delta.isNotEmpty) {
              yield delta;
            }
          } catch (_) {
            // ignore malformed chunks
          }
        }
      }
    }
  }

  /// Transcribe audio usando Groq Whisper API. Acepta bytes m4a/webm/wav/mp3.
  /// SIEMPRE va a Groq (OpenRouter no expone audio endpoints).
  Future<String> transcribe({
    required Uint8List audioBytes,
    String filename = 'audio.webm',
    String model = GroqModels.whisper,
    String language = 'es',
  }) async {
    final apiKey = _whisperApiKey;
    if (apiKey == null) {
      throw Exception(
        'GROQ_API_KEY missing for Whisper transcribe (audio is Groq-only).',
      );
    }

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(audioBytes, filename: filename),
      'model': model,
      'language': language,
      'response_format': 'json',
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '$_groqBaseUrl/audio/transcriptions',
      data: formData,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ),
    );

    return (response.data?['text'] as String? ?? '').trim();
  }

  /// Extrae el primer bloque JSON válido de un texto.
  /// Útil cuando el LLM envuelve el JSON en code fences u otro texto.
  static Map<String, dynamic>? extractJson(String text) {
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (jsonMatch == null) return null;
    try {
      return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
