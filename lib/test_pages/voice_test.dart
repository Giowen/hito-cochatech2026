import 'package:flutter/material.dart';
import 'package:record/record.dart';

/// Sprint 0.3 — Stack Test 2: validar que el package `record` captura audio
/// en Flutter Web con permisos del navegador (HTTPS o localhost exempt).
///
/// Done criteria:
/// - Browser pide permiso de micrófono al iniciar grabación
/// - Audio se captura sin errores (path o blob URL retornado)
class VoiceTestPage extends StatefulWidget {
  const VoiceTestPage({super.key});

  @override
  State<VoiceTestPage> createState() => _VoiceTestPageState();
}

class _VoiceTestPageState extends State<VoiceTestPage> {
  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String _status = 'Tap "Record" para validar acceso a micrófono';

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      try {
        final path = await _audioRecorder.stop();
        setState(() {
          _isRecording = false;
          _status = path != null
              ? '✓ PASS — audio captured.\nPath: $path'
              : '⚠ Stopped but no path returned';
        });
      } catch (e) {
        setState(() {
          _isRecording = false;
          _status = '❌ Stop error: $e';
        });
      }
    } else {
      try {
        final hasPermission = await _audioRecorder.hasPermission();
        if (!hasPermission) {
          setState(() => _status = '❌ Permission denied');
          return;
        }
        await _audioRecorder.start(
          const RecordConfig(),
          path: 'hito_recording.m4a',
        );
        setState(() {
          _isRecording = true;
          _status = '🔴 Recording... habla 5-10 segundos, luego Stop';
        });
      } catch (e) {
        setState(() => _status = '❌ Start error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test 2: record audio HTTPS'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isRecording ? Icons.mic : Icons.mic_none,
                size: 80,
                color: _isRecording ? Colors.red : Colors.grey,
              ),
              const SizedBox(height: 24),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _toggleRecording,
                icon: Icon(
                  _isRecording ? Icons.stop : Icons.fiber_manual_record,
                ),
                label: Text(_isRecording ? 'Stop' : 'Record'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
