import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import '../models/client_profile.dart';
import '../providers.dart';
import '../theme.dart';

/// VoiceInputSheet — modal sheet para input de perfil del cliente (Acto 1 wow #1).
///
/// Demo path: simula procesamiento 1.2s y retorna ClientProfile.demoJuan
/// (familia 2 hijos pequeños, \$220k USD máx, Recoleta, anticrético).
/// Real path: Whisper API + LLM extraction (Phase 2, ver ARCHITECTURE.md).
///
/// TODO R2: en producción, el audio capturado se sube a Cloudflare R2 vía
/// signed URL → trigger Whisper transcription server-side.
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
        _error = 'Error iniciando grabación: $e';
      });
    }
  }

  Future<void> _stopRecordingAndProcess() async {
    try {
      await _audioRecorder.stop();
      setState(() => _state = _SheetState.processing);

      // Demo path: simula Whisper + LLM extraction. Determinístico, cero red.
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
          24,
          16,
          24,
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
                    style: GoogleFonts.instrumentSerif(
                      fontSize: 24,
                      color: HitoTokens.ink1,
                      height: 1.1,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: HitoTokens.ink3),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Hablale a María como si fuera tu agente.',
              style: GoogleFonts.geist(
                fontSize: 13,
                color: HitoTokens.ink3,
              ),
            ),
            const SizedBox(height: 28),
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
            const SizedBox(height: 14),
            Center(
              child: Text(
                _statusText(),
                style: GoogleFonts.geist(
                  fontSize: 13,
                  color: _state == _SheetState.error
                      ? HitoTokens.danger
                      : HitoTokens.ink2,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: Column(
                children: [
                  if (_transcription.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _TranscriptionBubble(text: _transcription),
                  ],
                  if (_extractedProfile != null) ...[
                    const SizedBox(height: 12),
                    _ProfilePreview(profile: _extractedProfile!),
                  ],
                  if (_state == _SheetState.ready) ...[
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _applyProfile,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Buscar propiedades compatibles'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ] else if (_state == _SheetState.idle ||
                      _state == _SheetState.error) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _skipToDemoProfile,
                      icon: const Icon(Icons.skip_next_rounded, size: 16),
                      label: const Text('Saltar voz · usar perfil demo'),
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
        return 'Toca el botón y di lo que buscas\n(presupuesto, zona, modalidad, características).';
      case _SheetState.recording:
        return '🔴  Escuchando... habla con claridad,\ntoca de nuevo para detener.';
      case _SheetState.processing:
        return 'Whisper transcribiendo · Llama 3.3 estructurando perfil...';
      case _SheetState.ready:
        return '✓  Perfil listo. Revisa y confirma.';
      case _SheetState.error:
        return _error ?? 'Error desconocido';
    }
  }
}

class _MicButton extends StatelessWidget {
  final _SheetState state;
  final VoidCallback onPressed;

  const _MicButton({required this.state, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (state) {
      case _SheetState.recording:
        color = HitoTokens.danger;
        icon = Icons.stop_rounded;
      case _SheetState.processing:
        color = HitoTokens.teal;
        icon = Icons.hourglass_top_rounded;
      case _SheetState.ready:
        color = HitoTokens.success;
        icon = Icons.refresh_rounded;
      case _SheetState.error:
        color = HitoTokens.warning;
        icon = Icons.mic_rounded;
      case _SheetState.idle:
        color = HitoTokens.teal;
        icon = Icons.mic_rounded;
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
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3.5,
                  ),
                )
              : Icon(icon, color: Colors.white, size: 48),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HitoTokens.paper2,
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote_rounded,
            size: 18,
            color: HitoTokens.ink4,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.geist(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: HitoTokens.ink1,
                height: 1.5,
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HitoTokens.paper,
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        border: Border.all(color: HitoTokens.teal2, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_pin_rounded, color: HitoTokens.teal, size: 18),
              const SizedBox(width: 6),
              Text(
                'Perfil estructurado por AI',
                style: GoogleFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: HitoTokens.teal2,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row(
            context,
            Icons.attach_money_rounded,
            'Presupuesto: hasta \$${(profile.budgetMax / 1000 / 12.20).toStringAsFixed(0)}k USD',
          ),
          _row(
            context,
            Icons.swap_horiz_rounded,
            'Modalidad: ${profile.transactionType} ${profile.requiredTags.contains('acepta_anticretico') ? "+ anticrético" : ""}',
          ),
          _row(
            context,
            Icons.bed_outlined,
            'Mínimo ${profile.minBedrooms} dormitorios · ${profile.minAreaM2}+ m²',
          ),
          if (profile.requiredTags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: profile.requiredTags
                  .map(
                    (t) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: HitoTokens.paper2,
                        borderRadius: BorderRadius.circular(HitoTokens.rSm),
                      ),
                      child: Text(
                        t.replaceAll('_', ' '),
                        style: GoogleFonts.geist(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: HitoTokens.ink2,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: HitoTokens.ink3),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.geist(
                fontSize: 12.5,
                color: HitoTokens.ink1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
