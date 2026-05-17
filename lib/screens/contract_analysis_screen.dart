import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/contract_analysis.dart';
import '../providers.dart';
import '../services/pdf_text_extractor.dart';
import '../theme.dart';

/// "Tu Copiloto Legal Inmobiliario" — Acto 3 del pitch.
/// Dos modos:
///   - Análisis: lee `contractAnalysisProvider(propertyId)` (real Groq + cache).
///   - Borrador AI: usa `_draft` local generado on-demand desde el botón
///     "Generar borrador" en el AppBar.
class ContractAnalysisScreen extends ConsumerStatefulWidget {
  final String propertyId;
  const ContractAnalysisScreen({super.key, required this.propertyId});

  @override
  ConsumerState<ContractAnalysisScreen> createState() =>
      _ContractAnalysisScreenState();
}

class _ContractAnalysisScreenState
    extends ConsumerState<ContractAnalysisScreen> {
  ContractAnalysis? _draft;
  String? _draftType;
  bool _generating = false;
  String? _generateError;

  // ── Estado de "análisis de PDF subido" ──────────────────────────
  ContractAnalysis? _uploadedAnalysis;
  /// Hasta cuántas cláusulas mostrar mientras animamos el reveal progresivo.
  /// Cuando == analyzedClauses.length terminó.
  int _revealedClauses = 0;
  bool _analyzingUpload = false;
  String? _uploadError;
  String? _uploadFileName;

  bool get _showingDraft => _draft != null;
  bool get _showingUploaded => _uploadedAnalysis != null;

  Future<void> _openTypePicker() async {
    if (_generating) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ContractTypePicker(),
    );
    if (selected == null || !mounted) return;
    await _generate(selected);
  }

  Future<void> _generate(String contractType) async {
    setState(() {
      _generating = true;
      _generateError = null;
    });

    try {
      final propertiesAsync = ref.read(propertiesProvider);
      final properties = propertiesAsync.value;
      final property = properties == null
          ? null
          : {for (final p in properties) p.id: p}[widget.propertyId];
      if (property == null) {
        throw StateError('Property ${widget.propertyId} no encontrada');
      }

      final service = ref.read(contractAnalysisServiceProvider);
      final draft = await service.generateContractDraft(
        property: property,
        contractType: contractType,
      );

      if (!mounted) return;
      setState(() {
        _draft = draft;
        _draftType = contractType;
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _generateError = 'Error generando borrador: $e';
      });
    }
  }

  void _backToAnalysis() {
    setState(() {
      _draft = null;
      _draftType = null;
      _generateError = null;
      _uploadedAnalysis = null;
      _uploadFileName = null;
      _uploadError = null;
      _revealedClauses = 0;
    });
  }

  /// Flow: file_picker → bytes → extraer texto → analyzeContract con
  /// useCache=false (saltea el seed; queremos análisis fresco del PDF subido)
  /// → revealar cláusulas una por una con animación.
  Future<void> _pickAndAnalyzePdf() async {
    if (_analyzingUpload) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() {
        _uploadError = 'No se pudo leer el archivo. Probá de nuevo.';
      });
      return;
    }

    setState(() {
      _analyzingUpload = true;
      _uploadError = null;
      _uploadedAnalysis = null;
      _revealedClauses = 0;
      _uploadFileName = file.name;
      _draft = null;
      _draftType = null;
    });

    try {
      final text = await HitoPdfExtractor.extract(bytes);
      if (text.isEmpty) {
        if (!mounted) return;
        setState(() {
          _analyzingUpload = false;
          _uploadError =
              'No se pudo extraer texto. El PDF puede estar escaneado (sin OCR) o protegido.';
        });
        return;
      }

      final propertiesAsync = ref.read(propertiesProvider);
      final properties = propertiesAsync.value;
      final property = properties == null
          ? null
          : {for (final p in properties) p.id: p}[widget.propertyId];
      if (property == null) {
        throw StateError('Property ${widget.propertyId} no encontrada');
      }

      final service = ref.read(contractAnalysisServiceProvider);
      final analysis = await service.analyzeContract(
        property: property,
        contractText: text,
        contractType: 'anticretico',
        useCache: false, // saltea seed y cache — queremos análisis fresco del PDF
      );
      if (!mounted) return;
      setState(() {
        _uploadedAnalysis = analysis;
        _analyzingUpload = false;
      });
      _revealClausesProgressive(analysis.analyzedClauses.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzingUpload = false;
        _uploadError = 'Error analizando PDF: $e';
      });
    }
  }

  /// Revelado progresivo: muestra cada cláusula con 350ms de delay para
  /// dar sensación de "AI procesando una por una".
  void _revealClausesProgressive(int total) {
    Future<void>.delayed(const Duration(milliseconds: 200), () async {
      for (var i = 1; i <= total; i++) {
        if (!mounted || _uploadedAnalysis == null) return;
        setState(() => _revealedClauses = i);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HitoTokens.bone,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _showingDraft
              ? 'Borrador AI'
              : _showingUploaded
                  ? 'Análisis de PDF'
                  : 'Tu Copiloto Legal',
          style: hitoDisplay(
            fontSize: 22,
            color: HitoTokens.ink1,
            height: 1.0,
          ),
        ),
        backgroundColor: HitoTokens.bone,
        foregroundColor: HitoTokens.ink1,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (_showingDraft || _showingUploaded)
            TextButton.icon(
              onPressed: _backToAnalysis,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text(
                'Análisis',
                style: GoogleFonts.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                onPressed: _analyzingUpload ? null : _pickAndAnalyzePdf,
                style: TextButton.styleFrom(
                  foregroundColor: HitoTokens.teal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                icon: _analyzingUpload
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: HitoTokens.teal,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.upload_file_outlined, size: 16),
                label: Text(
                  _analyzingUpload ? 'Analizando…' : 'Subir PDF',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _generating ? null : _openTypePicker,
                style: FilledButton.styleFrom(
                  backgroundColor: HitoTokens.teal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                icon: _generating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(
                  _generating ? 'Generando...' : 'Generar borrador',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_generateError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 36, color: HitoTokens.danger),
              const SizedBox(height: 8),
              Text(_generateError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _openTypePicker,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_uploadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 36, color: HitoTokens.warning),
              const SizedBox(height: 8),
              Text(_uploadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _pickAndAnalyzePdf,
                child: const Text('Subir otro PDF'),
              ),
            ],
          ),
        ),
      );
    }

    if (_generating) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              'Llama 3.3 redactando borrador ${_draftType ?? ""}...',
              style: GoogleFonts.geist(
                fontSize: 13,
                color: HitoTokens.ink3,
              ),
            ),
          ],
        ),
      );
    }

    if (_analyzingUpload) {
      return _UploadAnalyzingSkeleton(fileName: _uploadFileName ?? 'contrato.pdf');
    }

    if (_showingDraft) {
      return _AnalysisBody(
        analysis: _draft!,
        isDraft: true,
        draftType: _draftType,
      );
    }

    if (_showingUploaded) {
      final clauses = _uploadedAnalysis!.analyzedClauses;
      final partial = clauses.take(_revealedClauses).toList();
      // Mostramos el análisis completo cuando termina el reveal; durante el
      // reveal, una versión parcial con clauses incompletas.
      final visible = _revealedClauses >= clauses.length
          ? _uploadedAnalysis!
          : _uploadedAnalysis!.copyWithClauses(partial);
      return _AnalysisBody(
        analysis: visible,
        isDraft: false,
        uploadFileName: _uploadFileName,
        revealing: _revealedClauses < clauses.length,
        revealedCount: _revealedClauses,
        totalClauses: clauses.length,
      );
    }

    final analysisAsync = ref.watch(contractAnalysisProvider(widget.propertyId));
    return analysisAsync.when(
      loading: () => const _CopilotoLoadingSkeleton(),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Error analizando contrato:\n$e'),
        ),
      ),
      data: (analysis) => _AnalysisBody(analysis: analysis, isDraft: false),
    );
  }
}

class _ContractTypePicker extends StatelessWidget {
  const _ContractTypePicker();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Generar borrador',
              style: hitoDisplay(
                fontSize: 22,
                color: HitoTokens.ink1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Elige el tipo de contrato. La IA arma una plantilla estándar '
              'con datos de la propiedad y placeholders para las partes.',
              style: GoogleFonts.geist(
                fontSize: 12,
                color: HitoTokens.ink3,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            _TypeOption(
              type: 'anticretico',
              label: 'Anticrético',
              description:
                  'Único en Bolivia. CC arts. 1429-1438. Entrega temporal de '
                  'capital restituible.',
              icon: Icons.swap_horiz_rounded,
            ),
            const SizedBox(height: 10),
            _TypeOption(
              type: 'compraventa',
              label: 'Compra-venta',
              description:
                  'Transferencia definitiva de propiedad. CC arts. 584-735.',
              icon: Icons.real_estate_agent_outlined,
            ),
            const SizedBox(height: 10),
            _TypeOption(
              type: 'alquiler',
              label: 'Alquiler',
              description:
                  'Uso temporal con pago periódico. Ley General del Inquilinato.',
              icon: Icons.calendar_month_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  final String type;
  final String label;
  final String description;
  final IconData icon;

  const _TypeOption({
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HitoTokens.paper,
      borderRadius: BorderRadius.circular(HitoTokens.rLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        onTap: () => Navigator.of(context).pop(type),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HitoTokens.rLg),
            border: Border.all(color: HitoTokens.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: HitoTokens.paper2,
                  borderRadius: BorderRadius.circular(HitoTokens.rMd),
                ),
                child: Icon(icon, color: HitoTokens.teal, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: HitoTokens.ink1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: GoogleFonts.geist(
                        fontSize: 11.5,
                        color: HitoTokens.ink3,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: HitoTokens.ink4,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalysisBody extends StatelessWidget {
  final ContractAnalysis analysis;
  final bool isDraft;
  final String? draftType;
  final String? uploadFileName;
  final bool revealing;
  final int revealedCount;
  final int totalClauses;

  const _AnalysisBody({
    required this.analysis,
    required this.isDraft,
    this.draftType,
    this.uploadFileName,
    this.revealing = false,
    this.revealedCount = 0,
    this.totalClauses = 0,
  });

  int _countByLevel(RiskLevel level) =>
      analysis.analyzedClauses.where((c) => c.riskLevel == level).length;

  @override
  Widget build(BuildContext context) {
    final redCount = _countByLevel(RiskLevel.high);
    final yellowCount = _countByLevel(RiskLevel.medium);
    final greenCount = _countByLevel(RiskLevel.low);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDraft) _DraftBanner(contractType: draftType ?? 'contrato'),
          if (isDraft) const SizedBox(height: 12),
          if (uploadFileName != null) ...[
            _UploadedBanner(
              fileName: uploadFileName!,
              revealing: revealing,
              revealedCount: revealedCount,
              total: totalClauses,
            ),
            const SizedBox(height: 12),
          ],
          _HeaderCard(
            contractType: analysis.contractType,
            isDraft: isDraft,
          ),
          const SizedBox(height: 14),
          _RiskScorePanel(
            score: analysis.overallRiskScore,
            redCount: redCount,
            yellowCount: yellowCount,
            greenCount: greenCount,
            isDraft: isDraft,
          ),
          if (analysis.gravamenCheck.isFlagged) ...[
            const SizedBox(height: 14),
            _GravamenAlert(check: analysis.gravamenCheck),
          ],
          const SizedBox(height: 14),
          _AiSummaryCard(text: analysis.summary, isDraft: isDraft),
          const SizedBox(height: 18),
          _SectionLabel(
            isDraft
                ? 'CLÁUSULAS DEL BORRADOR · ${analysis.analyzedClauses.length}'
                : 'CLÁUSULAS ANALIZADAS · ${analysis.analyzedClauses.length}',
          ),
          const SizedBox(height: 10),
          _HighlightedContractView(
            contractText: analysis.contractText,
            clauses: analysis.analyzedClauses,
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < analysis.analyzedClauses.length; i++) ...[
            _ClauseCard(
              n: i + 1,
              clause: analysis.analyzedClauses[i],
            ),
            const SizedBox(height: 8),
          ],
          if (analysis.fraudPatternsDetected.isNotEmpty) ...[
            const SizedBox(height: 6),
            const _SectionLabel('PATRONES DE FRAUDE DETECTADOS'),
            const SizedBox(height: 6),
            for (final pattern in analysis.fraudPatternsDetected)
              _BulletItem(
                icon: Icons.warning_amber_rounded,
                color: HitoTokens.danger,
                text: pattern,
              ),
          ],
          const SizedBox(height: 18),
          _SectionLabel(
            isDraft ? 'PRÓXIMOS PASOS' : 'RECOMENDACIONES ACCIONABLES',
          ),
          const SizedBox(height: 6),
          for (final rec in analysis.recommendations)
            _BulletItem(
              icon: Icons.check_circle_outline_rounded,
              color: HitoTokens.teal,
              text: rec,
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Volver'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: HitoTokens.ink2,
                        content: Text(
                          'PDF export disponible en Phase 2 (R2 upload + render server-side)',
                          style: GoogleFonts.geist(color: Colors.white),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Descargar PDF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DraftBanner extends StatelessWidget {
  final String contractType;
  const _DraftBanner({required this.contractType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: HitoTokens.teal.withAlpha(20),
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: HitoTokens.teal.withAlpha(100)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: HitoTokens.teal, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'BORRADOR GENERADO · Plantilla estándar AI. Completá '
              'placeholders [CORCHETES] antes de firmar.',
              style: GoogleFonts.geist(
                fontSize: 11,
                color: HitoTokens.teal2,
                height: 1.4,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String contractType;
  final bool isDraft;
  const _HeaderCard({required this.contractType, required this.isDraft});

  @override
  Widget build(BuildContext context) {
    final isAnticretico = contractType == 'anticretico';
    final typeLabel = contractType.isEmpty
        ? 'contrato'
        : '${contractType[0].toUpperCase()}${contractType.substring(1)}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HitoTokens.paper,
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HitoTokens.paper2,
              borderRadius: BorderRadius.circular(HitoTokens.rMd),
            ),
            child: Icon(
              isDraft ? Icons.auto_awesome : Icons.shield_outlined,
              color: HitoTokens.teal,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDraft
                      ? 'Borrador de $typeLabel'
                      : 'Contrato de $typeLabel',
                  style: GoogleFonts.geist(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: HitoTokens.ink1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isAnticretico
                      ? 'CC Bolivia arts. 1429-1438 · instrumento único de Bolivia'
                      : isDraft
                          ? 'Plantilla AI conforme a derecho boliviano'
                          : 'Análisis legal automático con AI boliviana',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    color: HitoTokens.ink3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskScorePanel extends StatelessWidget {
  final int score;
  final int redCount;
  final int yellowCount;
  final int greenCount;
  final bool isDraft;

  const _RiskScorePanel({
    required this.score,
    required this.redCount,
    required this.yellowCount,
    required this.greenCount,
    required this.isDraft,
  });

  Color _color() {
    if (score >= 70) return HitoTokens.danger;
    if (score >= 40) return HitoTokens.warning;
    return HitoTokens.success;
  }

  String _label() {
    if (score >= 70) return 'Alto';
    if (score >= 40) return 'Medio';
    return 'Bajo';
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HitoTokens.paper,
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isDraft ? 'NIVEL DE PLANTILLA' : 'RIESGO',
                style: GoogleFonts.geist(
                  fontSize: 10,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600,
                  color: HitoTokens.ink4,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    (score / 10).toStringAsFixed(1),
                    style: hitoDisplay(
                      fontSize: 36,
                      color: color,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    '/10',
                    style: GoogleFonts.geist(
                      fontSize: 12,
                      color: HitoTokens.ink4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(HitoTokens.r2xl),
                    ),
                    child: Text(
                      isDraft ? 'Limpio' : _label(),
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          _CountPill(count: redCount, color: HitoTokens.danger),
          const SizedBox(width: 6),
          _CountPill(count: yellowCount, color: HitoTokens.warning),
          const SizedBox(width: 6),
          _CountPill(count: greenCount, color: HitoTokens.success),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;
  final Color color;
  const _CountPill({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        '$count',
        style: GoogleFonts.geist(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _GravamenAlert extends StatelessWidget {
  final GravamenCheck check;
  const _GravamenAlert({required this.check});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HitoTokens.dangerBg,
        border: Border.all(color: HitoTokens.danger, width: 1.2),
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: HitoTokens.danger,
              borderRadius: BorderRadius.circular(HitoTokens.rMd),
            ),
            child: const Icon(
              Icons.gpp_bad_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GRAVAMEN DETECTADO',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: HitoTokens.danger,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  check.details,
                  style: GoogleFonts.geist(
                    fontSize: 13,
                    color: HitoTokens.ink1,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cruce con base de Derechos Reales · hace minutos',
                  style: GoogleFonts.geist(
                    fontSize: 10,
                    color: HitoTokens.danger,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSummaryCard extends StatelessWidget {
  final String text;
  final bool isDraft;
  const _AiSummaryCard({required this.text, required this.isDraft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HitoTokens.paper2,
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: HitoTokens.teal, size: 16),
              const SizedBox(width: 6),
              Text(
                isDraft ? 'Resumen del borrador' : 'AI análisis ejecutivo',
                style: GoogleFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: HitoTokens.teal2,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: GoogleFonts.geist(
              fontSize: 13,
              color: HitoTokens.ink1,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.geist(
        fontSize: 10,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w600,
        color: HitoTokens.ink4,
      ),
    );
  }
}

/// Render del contrato con cláusulas highlighted. Cachea los spans para no
/// recalcular en cada build — antes el fuzzy matching O(N*M) corría cada
/// rebuild del widget (~32M ops para 13 cláusulas x 5000 chars) y freezaba
/// la UI haciendo parecer que la app colgó.
class _HighlightedContractView extends StatefulWidget {
  final String contractText;
  final List<AnalyzedClause> clauses;
  const _HighlightedContractView({
    required this.contractText,
    required this.clauses,
  });

  @override
  State<_HighlightedContractView> createState() =>
      _HighlightedContractViewState();
}

class _HighlightedContractViewState extends State<_HighlightedContractView> {
  static final _wsRe = RegExp(r'\s+');

  List<TextSpan>? _cachedSpans;
  // Identidad-clave para invalidar el cache cuando cambian los inputs.
  int? _lastContractHash;
  int? _lastClausesHash;

  Color _bgFor(RiskLevel level) {
    switch (level) {
      case RiskLevel.high:
        return const Color(0x66F87171);
      case RiskLevel.medium:
        return const Color(0x55F59E0B);
      case RiskLevel.low:
        return const Color(0x4410B981);
    }
  }

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(_wsRe, ' ').trim();

  /// Busca [needle] en [haystack]. Estrategia escalada por costo:
  ///   1. `indexOf` exacto (O(N+M), nativo) — funciona para SEED contracts
  ///      donde la cláusula es cita literal del texto.
  ///   2. Fallback fuzzy con normalización (solo si exacto falla) —
  ///      cubre el caso del LLM que cita con comillas/espacios distintos.
  ///
  /// Devuelve (start, end) en coords del haystack original o null.
  (int, int)? _findClauseRange(String haystack, String needle) {
    if (needle.isEmpty) return null;
    // Fast path: exact match. Para SEED contracts esto siempre acierta.
    final exact = haystack.indexOf(needle);
    if (exact >= 0) return (exact, exact + needle.length);

    // Slow path: normalized fuzzy.
    final hNorm = _normalize(haystack);
    final nNorm = _normalize(needle);
    if (nNorm.isEmpty) return null;
    final idxNorm = hNorm.indexOf(nNorm);
    if (idxNorm < 0) return null;

    int orig = 0;
    int norm = 0;
    while (orig < haystack.length && norm < idxNorm) {
      final c = haystack[orig];
      if (_wsRe.hasMatch(c)) {
        while (orig < haystack.length && _wsRe.hasMatch(haystack[orig])) {
          orig++;
        }
        norm++;
      } else {
        orig++;
        norm++;
      }
    }
    final start = orig;
    int endNorm = 0;
    int end = start;
    while (end < haystack.length && endNorm < nNorm.length) {
      final c = haystack[end];
      if (_wsRe.hasMatch(c)) {
        while (end < haystack.length && _wsRe.hasMatch(haystack[end])) {
          end++;
        }
        endNorm++;
      } else {
        end++;
        endNorm++;
      }
    }
    return (start, end);
  }

  List<TextSpan> _buildSpans() {
    final positions = <_Span>[];
    for (final clause in widget.clauses) {
      final range = _findClauseRange(widget.contractText, clause.clauseText);
      if (range != null) {
        positions.add(_Span(
          start: range.$1,
          end: range.$2,
          clause: clause,
        ));
      }
    }
    positions.sort((a, b) => a.start.compareTo(b.start));

    final nonOverlap = <_Span>[];
    for (final pos in positions) {
      if (nonOverlap.isEmpty || pos.start >= nonOverlap.last.end) {
        nonOverlap.add(pos);
      }
    }

    final spans = <TextSpan>[];
    int cursor = 0;
    for (final pos in nonOverlap) {
      if (pos.start > cursor) {
        spans.add(
            TextSpan(text: widget.contractText.substring(cursor, pos.start)));
      }
      spans.add(TextSpan(
        text: widget.contractText.substring(pos.start, pos.end),
        style: TextStyle(
          backgroundColor: _bgFor(pos.clause.riskLevel),
          fontWeight: FontWeight.w500,
        ),
      ));
      cursor = pos.end;
    }
    if (cursor < widget.contractText.length) {
      spans.add(TextSpan(text: widget.contractText.substring(cursor)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    // Recalcular spans solo cuando cambian inputs (no en cada rebuild).
    final contractHash = widget.contractText.hashCode;
    final clausesHash = Object.hashAll(widget.clauses.map((c) => c.clauseText));
    if (_cachedSpans == null ||
        _lastContractHash != contractHash ||
        _lastClausesHash != clausesHash) {
      _cachedSpans = _buildSpans();
      _lastContractHash = contractHash;
      _lastClausesHash = clausesHash;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HitoTokens.paper,
        border: Border.all(color: HitoTokens.border),
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
      ),
      constraints: const BoxConstraints(maxHeight: 360),
      child: SingleChildScrollView(
        child: RichText(
          text: TextSpan(
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11.5,
              color: HitoTokens.ink2,
              height: 1.7,
            ),
            children: _cachedSpans!,
          ),
        ),
      ),
    );
  }
}

class _Span {
  final int start;
  final int end;
  final AnalyzedClause clause;
  _Span({required this.start, required this.end, required this.clause});
}

class _ClauseCard extends StatelessWidget {
  final int n;
  final AnalyzedClause clause;
  const _ClauseCard({required this.n, required this.clause});

  Color _color() {
    switch (clause.riskLevel) {
      case RiskLevel.high:
        return HitoTokens.danger;
      case RiskLevel.medium:
        return HitoTokens.warning;
      case RiskLevel.low:
        return HitoTokens.success;
    }
  }

  String _label() {
    switch (clause.riskLevel) {
      case RiskLevel.high:
        return 'RIESGO ALTO';
      case RiskLevel.medium:
        return 'REVISAR';
      case RiskLevel.low:
        return 'ESTÁNDAR';
    }
  }

  IconData _icon() {
    switch (clause.riskLevel) {
      case RiskLevel.high:
        return Icons.error_outline_rounded;
      case RiskLevel.medium:
        return Icons.warning_amber_rounded;
      case RiskLevel.low:
        return Icons.check_circle_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HitoTokens.paper,
        border: Border.all(color: color.withAlpha(80)),
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$n',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(_icon(), size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                _label(),
                style: GoogleFonts.geist(
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '"${clause.clauseText}"',
            style: GoogleFonts.geist(
              fontSize: 11.5,
              color: HitoTokens.ink2,
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
          if (clause.issue.isNotEmpty) ...[
            const SizedBox(height: 8),
            _kvRow(context, 'Problema', clause.issue),
          ],
          if (clause.suggestion.isNotEmpty &&
              clause.suggestion != 'Sin cambios.' &&
              clause.suggestion != 'Sin cambios necesarios.') ...[
            const SizedBox(height: 4),
            _kvRow(context, 'Sugerencia', clause.suggestion),
          ],
        ],
      ),
    );
  }

  Widget _kvRow(BuildContext context, String label, String value) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.geist(
          fontSize: 12,
          color: HitoTokens.ink2,
          height: 1.45,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _BulletItem({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.geist(
                fontSize: 12.5,
                color: HitoTokens.ink2,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner que se muestra cuando el análisis vino de un PDF subido por el
/// usuario, con un contador "leyendo cláusula X de Y" durante el reveal.
class _UploadedBanner extends StatelessWidget {
  final String fileName;
  final bool revealing;
  final int revealedCount;
  final int total;
  const _UploadedBanner({
    required this.fileName,
    required this.revealing,
    required this.revealedCount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: HitoTokens.navy.withAlpha(15),
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: HitoTokens.navy.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(Icons.upload_file_rounded, color: HitoTokens.navy, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PDF SUBIDO · $fileName',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: HitoTokens.navy,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  revealing
                      ? 'Procesando cláusula $revealedCount de $total…'
                      : 'Análisis completo · $total cláusulas evaluadas',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    color: HitoTokens.ink3,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (revealing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

/// Pantalla full-screen mientras Groq analiza un PDF recién subido.
/// Skeleton de cards de cláusulas + mensajes rotativos del pipeline.
class _UploadAnalyzingSkeleton extends StatefulWidget {
  final String fileName;
  const _UploadAnalyzingSkeleton({required this.fileName});

  @override
  State<_UploadAnalyzingSkeleton> createState() =>
      _UploadAnalyzingSkeletonState();
}

class _UploadAnalyzingSkeletonState extends State<_UploadAnalyzingSkeleton>
    with SingleTickerProviderStateMixin {
  static const _messages = [
    'Extrayendo texto del PDF…',
    'Identificando cláusulas y partes del contrato…',
    'Cruzando con Código Civil boliviano (arts. 1429-1438)…',
    'Detectando patrones de fraude documental…',
    'Verificando estado registral en Derechos Reales…',
    'Calculando score de riesgo ponderado…',
    'Redactando recomendaciones accionables…',
  ];
  int _index = 0;
  Timer? _timer;
  late AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      duration: const Duration(milliseconds: 1300),
      vsync: this,
    )..repeat();
    _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HitoTokens.teal.withAlpha(15),
              borderRadius: BorderRadius.circular(HitoTokens.rLg),
              border: Border.all(color: HitoTokens.teal.withAlpha(80)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: HitoTokens.teal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ANALIZANDO ${widget.fileName}',
                        style: GoogleFonts.geist(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: HitoTokens.teal2,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _messages[_index],
                          key: ValueKey(_index),
                          style: GoogleFonts.geist(
                            fontSize: 12.5,
                            color: HitoTokens.ink1,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SkeletonBlock(shimmer: _shimmer, height: 90),
          const SizedBox(height: 14),
          _SkeletonBlock(shimmer: _shimmer, height: 60),
          const SizedBox(height: 18),
          for (var i = 0; i < 5; i++) ...[
            _SkeletonClauseCard(shimmer: _shimmer),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Skeleton para el flow de seed/cache-hit que no debería tardar pero que
/// si tarda (ej. demora de Supabase) muestra un placeholder con shimmer.
class _CopilotoLoadingSkeleton extends StatefulWidget {
  const _CopilotoLoadingSkeleton();

  @override
  State<_CopilotoLoadingSkeleton> createState() =>
      _CopilotoLoadingSkeletonState();
}

class _CopilotoLoadingSkeletonState extends State<_CopilotoLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      duration: const Duration(milliseconds: 1300),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SkeletonBlock(shimmer: _shimmer, height: 72),
          const SizedBox(height: 14),
          _SkeletonBlock(shimmer: _shimmer, height: 88),
          const SizedBox(height: 18),
          for (var i = 0; i < 4; i++) ...[
            _SkeletonClauseCard(shimmer: _shimmer),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final AnimationController shimmer;
  final double height;
  const _SkeletonBlock({required this.shimmer, required this.height});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmer,
      builder: (context, _) {
        final t = shimmer.value;
        return Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, 0),
              end: Alignment(0 + 2 * t, 0),
              colors: [
                HitoTokens.paper3,
                HitoTokens.paper,
                HitoTokens.paper3,
              ],
            ),
            borderRadius: BorderRadius.circular(HitoTokens.rLg),
            border: Border.all(color: HitoTokens.border),
          ),
        );
      },
    );
  }
}

class _SkeletonClauseCard extends StatelessWidget {
  final AnimationController shimmer;
  const _SkeletonClauseCard({required this.shimmer});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return AnimatedBuilder(
          animation: shimmer,
          builder: (context, _) {
            final t = shimmer.value;
            // Pre-calculamos width absoluto en vez de usar FractionallySizedBox
            // (que rompe dentro de Row porque queda sin constraint horizontal).
            Widget bar({required double widthFactor, double height = 10}) {
              return Container(
                width: w * widthFactor,
                height: height,
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1 + 2 * t, 0),
                    end: Alignment(0 + 2 * t, 0),
                    colors: [
                      HitoTokens.paper3,
                      HitoTokens.paper,
                      HitoTokens.paper3,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HitoTokens.paper,
                border: Border.all(color: HitoTokens.border),
                borderRadius: BorderRadius.circular(HitoTokens.rMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: HitoTokens.paper3,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      bar(widthFactor: 0.22, height: 8),
                    ],
                  ),
                  const SizedBox(height: 10),
                  bar(widthFactor: 0.95),
                  bar(widthFactor: 0.85),
                  bar(widthFactor: 0.6),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
