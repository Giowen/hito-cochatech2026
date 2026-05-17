import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/client_profile.dart';
import '../models/lead.dart';
import '../providers.dart';
import '../theme.dart';
import '../utils/tc_paralelo.dart';
import 'top_banner.dart';

/// VoiceInputSheet — captura voz del usuario, transcribe con Whisper (Groq),
/// extrae perfil estructurado con Llama 3.3, y aplica a clientProfileProvider.
///
/// **Sin atajo demo**: cada query es voz real → transcripción real → JSON
/// parseado por LLM. El profile resultante invalida el cache de matching
/// (nuevo profileHash) y dispara 12 Groq calls frescos.
class VoiceInputSheet extends ConsumerStatefulWidget {
  const VoiceInputSheet({super.key});

  @override
  ConsumerState<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

enum _SheetState { idle, recording, transcribing, extracting, ready, error }

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
          _error = 'Permiso de micrófono denegado. Activa el micrófono en '
              'la configuración del navegador y vuelve a intentar.';
        });
        return;
      }
      // En Web `path` es ignorado (devuelve blob:); en mobile/desktop debe
      // ser ruta absoluta a un directorio writable. Antes usaba ruta
      // relativa "hito_profile_input.m4a" que falla en algunos dispositivos.
      final path = kIsWeb
          ? 'hito_profile_input.m4a'
          : '${(await getTemporaryDirectory()).path}/hito_profile_input.m4a';
      await _audioRecorder.start(const RecordConfig(), path: path);
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
    String? audioUrl;
    try {
      audioUrl = await _audioRecorder.stop();
    } catch (e) {
      setState(() {
        _state = _SheetState.error;
        _error = 'Error deteniendo grabación: $e';
      });
      return;
    }
    if (audioUrl == null) {
      setState(() {
        _state = _SheetState.error;
        _error = 'No se obtuvo audio. Intenta de nuevo.';
      });
      return;
    }

    final service = ref.read(voiceToProfileServiceProvider);

    // Step 1: leer bytes
    setState(() => _state = _SheetState.transcribing);
    try {
      final bytes = await service.audioFromUrl(audioUrl);

      // Step 2: Whisper transcribe
      final transcript = await service.transcribe(bytes);
      if (!mounted) return;
      if (transcript.isEmpty) {
        setState(() {
          _state = _SheetState.error;
          _error =
              'Whisper no detectó audio. Habla más fuerte y vuelve a probar.';
        });
        return;
      }
      setState(() {
        _transcription = transcript;
        _state = _SheetState.extracting;
      });

      // Step 3: Llama extract → ClientProfile
      final profile = await service.extractProfile(transcript);
      if (!mounted) return;
      setState(() {
        _extractedProfile = profile;
        _state = _SheetState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _SheetState.error;
        _error = 'Error procesando voz: $e';
      });
    }
  }

  Future<void> _applyProfile() async {
    if (_extractedProfile == null) return;
    ref.read(clientProfileProvider.notifier).update(_extractedProfile!);
    ref.invalidate(matchResultsProvider);

    // Si está en vista cliente, esta voice query crea un lead en el inbox
    // del agente — el flujo "ecosistema dual" del desafío. Si está en vista
    // agente buscando inventario propio, no creamos lead (sería ruido).
    final viewMode = ref.read(viewModeProvider);
    final isClient = viewMode == ViewMode.client;
    if (isClient) {
      final shareSource = ref.read(shareLinkOriginProvider);
      // ignore: discarded_futures
      ref.read(leadsProvider.notifier).addFromVoice(
            profile: _extractedProfile!,
            source: shareSource ? LeadSource.shareLink : LeadSource.organic,
          );
    }

    // Capturar la referencia al overlay ANTES del pop. Después del pop, el
    // context del sheet queda muerto, pero el OverlayState del root nav
    // sigue vivo.
    final rootNav = Navigator.of(context, rootNavigator: true);
    final overlayState = rootNav.overlay;

    Navigator.of(context).pop();

    if (isClient && overlayState != null) {
      // Insertar el banner directamente en el overlay capturado, sin pasar
      // por TopBanner.show (que necesita un context vivo). Usamos el mismo
      // OverlayEntry pattern.
      _showBannerOnOverlay(
        overlayState,
        message: 'Tu búsqueda se envió a María. Te contactará pronto.',
        icon: Icons.send_rounded,
      );
    }
  }

  /// Inserta el banner usando un OverlayState ya resuelto. Evita race
  /// condition de `Overlay.of(context)` después de un pop.
  void _showBannerOnOverlay(
    OverlayState overlay, {
    required String message,
    required IconData icon,
  }) {
    // Reusa TopBanner.show pasando el context del overlay (es válido por
    // estar dentro del subtree de Overlay). TopBanner se encarga del resto.
    TopBanner.show(overlay.context, message: message, icon: icon);
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
                    style: hitoDisplay(
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
              'Háblale a María como si fuera tu agente.',
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
                        backgroundColor: HitoTokens.teal,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
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
        return 'Toca el botón y di lo que buscas\n'
            '(presupuesto, zona, modalidad, características).';
      case _SheetState.recording:
        return '🔴  Escuchando... habla con claridad,\n'
            'toca de nuevo para detener.';
      case _SheetState.transcribing:
        return 'Whisper transcribiendo el audio...';
      case _SheetState.extracting:
        return 'Llama 3.3 estructurando tu perfil...';
      case _SheetState.ready:
        return '✓  Perfil listo. Revísalo y confirma.';
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
      case _SheetState.transcribing:
      case _SheetState.extracting:
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

    final processing = state == _SheetState.transcribing ||
        state == _SheetState.extracting;

    return Material(
      shape: const CircleBorder(),
      elevation: state == _SheetState.recording ? 8 : 4,
      color: color,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: processing ? null : onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: state == _SheetState.recording ? 130 : 110,
          height: state == _SheetState.recording ? 130 : 110,
          alignment: Alignment.center,
          child: processing
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
            'Presupuesto: hasta \$${(profile.budgetMax / 1000 / TcParalelo.rate).toStringAsFixed(0)}k USD',
          ),
          _row(
            context,
            Icons.swap_horiz_rounded,
            'Modalidad: ${profile.transactionType}${profile.requiredTags.contains('acepta_anticretico') ? " + anticrético" : ""}',
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
