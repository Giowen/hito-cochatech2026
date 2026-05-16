import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:dio/dio.dart';

/// Sprint 0.4 — Stack Test 3: validar que Groq Llama 3.3 streaming responde
/// con primer token en <2s.
///
/// Done criteria:
/// - Groq responde sin errores de auth
/// - First token latency <2000ms
/// - Streaming entrega tokens incrementalmente
class GroqTestPage extends StatefulWidget {
  const GroqTestPage({super.key});

  @override
  State<GroqTestPage> createState() => _GroqTestPageState();
}

class _GroqTestPageState extends State<GroqTestPage> {
  final _dio = Dio();
  String _output = 'Tap "Test Groq" para validar streaming';
  bool _testing = false;
  Duration? _firstTokenLatency;
  Duration? _totalLatency;

  Future<void> _testGroq() async {
    setState(() {
      _testing = true;
      _output = 'Conectando a Groq...';
      _firstTokenLatency = null;
      _totalLatency = null;
    });

    final apiKey = dotenv.env['GROQ_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _output = '❌ GROQ_API_KEY missing or empty in .env';
        _testing = false;
      });
      return;
    }

    final stopwatch = Stopwatch()..start();
    final buffer = StringBuffer();
    Duration? firstTokenAt;

    try {
      final response = await _dio.post<ResponseBody>(
        'https://api.groq.com/openai/v1/chat/completions',
        data: {
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {
              'role': 'user',
              'content':
                  'Responde en máximo 20 palabras: ¿qué es el anticrético en Bolivia?',
            }
          ],
          'stream': true,
          'temperature': 0.3,
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
                if (firstTokenAt == null) {
                  firstTokenAt = stopwatch.elapsed;
                  setState(() => _firstTokenLatency = firstTokenAt);
                }
                buffer.write(delta);
                setState(() => _output = buffer.toString());
              }
            } catch (_) {
              // ignore malformed chunks
            }
          }
        }
      }
      setState(() {
        _testing = false;
        _totalLatency = stopwatch.elapsed;
      });
    } catch (e) {
      setState(() {
        _output = '❌ Error: $e';
        _testing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pass =
        _firstTokenLatency != null && _firstTokenLatency! < const Duration(seconds: 2);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test 3: Groq streaming'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton.icon(
              onPressed: _testing ? null : _testGroq,
              icon: const Icon(Icons.bolt),
              label: Text(_testing ? 'Streaming...' : 'Test Groq Streaming'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_firstTokenLatency != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: pass ? Colors.green.shade50 : Colors.orange.shade50,
                  border: Border.all(
                    color: pass ? Colors.green : Colors.orange,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${pass ? "✓ PASS" : "⚠ SLOW"}: '
                  'first token in ${_firstTokenLatency!.inMilliseconds}ms '
                  '(target <2000ms)'
                  '${_totalLatency != null ? "\nTotal: ${_totalLatency!.inMilliseconds}ms" : ""}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: pass ? Colors.green.shade800 : Colors.orange.shade800,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _output,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
