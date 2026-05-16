import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Cliente para Groq API (OpenAI-compatible).
/// Soporta chat completion non-streaming y streaming.
class GroqClient {
  final Dio _dio;
  static const String _baseUrl = 'https://api.groq.com/openai/v1';

  GroqClient({Dio? dio}) : _dio = dio ?? Dio();

  String? get _apiKey {
    final key = dotenv.env['GROQ_API_KEY'];
    if (key == null || key.isEmpty) return null;
    return key;
  }

  /// Chat completion non-streaming. Retorna el texto completo de la respuesta.
  Future<String> chat({
    required List<Map<String, String>> messages,
    String model = 'llama-3.3-70b-versatile',
    double temperature = 0.3,
    Map<String, dynamic>? responseFormat,
  }) async {
    final apiKey = _apiKey;
    if (apiKey == null) {
      throw Exception('GROQ_API_KEY missing or empty in .env');
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
    };
    if (responseFormat != null) {
      body['response_format'] = responseFormat;
    }

    final response = await _dio.post<Map<String, dynamic>>(
      '$_baseUrl/chat/completions',
      data: body,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );

    final content = response.data!['choices'][0]['message']['content'] as String;
    return content;
  }

  /// Chat completion streaming. Yields deltas de contenido token-by-token.
  Stream<String> chatStream({
    required List<Map<String, String>> messages,
    String model = 'llama-3.3-70b-versatile',
    double temperature = 0.3,
  }) async* {
    final apiKey = _apiKey;
    if (apiKey == null) {
      throw Exception('GROQ_API_KEY missing or empty in .env');
    }

    final response = await _dio.post<ResponseBody>(
      '$_baseUrl/chat/completions',
      data: {
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'stream': true,
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
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
