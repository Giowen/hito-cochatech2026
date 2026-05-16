import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import '../models/client_profile.dart';
import '../providers.dart';

/// VoiceInputSheet — modal sheet para input de perfil del cliente.
/// Default demo path: hardcoded result tras simular procesamiento.
/// Real path: Whisper + Llama extraction (TODO Sprint 2.2 advanced).
class VoiceInputSheet extends ConsumerStatefulWidget {
  const VoiceInputSheet({super.key});

  @override
  ConsumerState<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

enum _SheetState { idle, recording, processing, ready, error }

class _VoiceInputSheetState extends ConsumerState<VoiceInputSheet> {
  final _audioRecorder = AudioRecorder();
  _SheetState _state = _SheetState.idle;
  String _transcription = '';
  ClientProfile? _extractedProfile;
  String? _error;

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        setState(() {
          _state = _SheetState.error;
          _error = 'Permiso de micrófono denegado';
        });
        return;
      }
      await _audioRecorder.start(
        const RecordConfig(),
        path: 'hito_profile_input.m4a',
      );
      setState(() {
        _state = _SheetState.recording;
        _transcription = '';
        _extractedProfile = null;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _state = _SheetState.error;
        _error = 'Error: $e';
      });
    }
  }

  Future<void> _stopRecordingAndProcess() async {
    try {
      await _audioRecorder.stop();
      setState(() => _state = _SheetState.processing);

      // Demo path: simulate Whisper + LLM extraction
      await Future.delayed(const Duration(milliseconds: 1200));
      setState(() {
        _transcription = ClientProfile.demoJuan.voiceInputTranscript!;
        _extractedProfile = ClientProfile.demoJuan;
        _state = _SheetState.ready;
      });
    } catch (e) {
      setState(() {
        _state = _SheetState.error;
        _error = 'Error procesando: $e';
      });
    }
  }

  void _skipToDemoProfile() {
    setState(() {
      _transcription = ClientProfile.demoJuan.voiceInputTranscript!;
      _extractedProfile = ClientProfile.demoJuan;
      _state = _SheetState.ready;
    });
  }

  void _applyProfile() {
    if (_extractedProfile == null) return;
    ref.read(clientProfileProvider.notifier).update(_extractedProfile!);
    ref.invalidate(matchResultsProvider);
    Navigator.of(context).pop();
  }

  void _reset() {
    setState(() {
      _state = _SheetState.idle;
      _transcription = '';
      _extractedProfile = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '¿Qué casa estás buscando?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: _MicButton(
                state: _state,
                onPressed: () {
                  if (_state == _SheetState.recording) {
                    _stopRecordingAndProcess();
                  } else if (_state == _SheetState.idle ||
                      _state == _SheetState.error) {
                    _startRecording();
                  } else if (_state == _SheetState.ready) {
                    _reset();
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _statusText(),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: Column(
                children: [
                  if (_transcription.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _TranscriptionBubble(text: _transcription),
                  ],
                  if (_extractedProfile != null) ...[
                    const SizedBox(height: 12),
                    _ProfilePreview(profile: _extractedProfile!),
                  ],
                  if (_state == _SheetState.ready) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _applyProfile,
                      icon: const Icon(Icons.search),
                      label: const Text('Buscar propiedades'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ] else if (_state == _SheetState.idle ||
                      _state == _SheetState.error) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _skipToDemoProfile,
                      icon: const Icon(Icons.skip_next, size: 18),
                      label: const Text('Saltar voz, usar perfil de Juan'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText() {
    switch (_state) {
      case _SheetState.idle:
        return 'Toca el botón y di lo que buscas\n(presupuesto, zona, modalidad, características)';
      case _SheetState.recording:
        return '🔴 Escuchando... habla con claridad,\ntoca de nuevo para detener';
      case _SheetState.processing:
        return 'Whisper transcribiendo y Llama 3.3\nestructurando perfil...';
      case _SheetState.ready:
        return '✓ Perfil listo. Revisa y confirma.';
      case _SheetState.error:
        return '❌ ${_error ?? "Error desconocido"}';
    }
  }
}

class _MicButton extends StatelessWidget {
  final _SheetState state;
  final VoidCallback onPressed;

  const _MicButton({required this.state, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color color;
    IconData icon;

    switch (state) {
      case _SheetState.recording:
        color = Colors.red.shade600;
        icon = Icons.stop_rounded;
      case _SheetState.processing:
        color = scheme.primary;
        icon = Icons.hourglass_top;
      case _SheetState.ready:
        color = Colors.green.shade600;
        icon = Icons.refresh;
      case _SheetState.error:
        color = Colors.orange.shade700;
        icon = Icons.mic;
      case _SheetState.idle:
        color = scheme.primary;
        icon = Icons.mic;
    }

    return Material(
      shape: const CircleBorder(),
      elevation: state == _SheetState.recording ? 8 : 4,
      color: color,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: state == _SheetState.processing ? null : onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: state == _SheetState.recording ? 130 : 110,
          height: state == _SheetState.recording ? 130 : 110,
          alignment: Alignment.center,
          child: state == _SheetState.processing
              ? const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 4,
                  ),
                )
              : Icon(icon, color: Colors.white, size: 52),
        ),
      ),
    );
  }
}

class _TranscriptionBubble extends StatelessWidget {
  final String text;
  const _TranscriptionBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote,
            size: 18,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePreview extends StatelessWidget {
  final ClientProfile profile;
  const _ProfilePreview({required this.profile});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withAlpha(80),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_pin, color: scheme.primary, size: 18),
              const SizedBox(width: 6),
              Text(
                'Perfil extraído',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _row(
            context,
            Icons.attach_money,
            '${profile.budgetMin ~/ 1000}K - ${profile.budgetMax ~/ 1000}K Bs',
          ),
          _row(
            context,
            Icons.swap_horiz,
            'Modalidad: ${profile.transactionType}',
          ),
          _row(
            context,
            Icons.bed_outlined,
            'Mínimo ${profile.minBedrooms} dormitorios',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: profile.requiredTags
                .map(
                  (t) => Chip(
                    label: Text(t.replaceAll('_', ' ')),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 11),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
