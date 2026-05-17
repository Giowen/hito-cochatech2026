import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/contract_analysis.dart';
import '../providers.dart';
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

  bool get _showingDraft => _draft != null;

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
          _showingDraft ? 'Borrador AI' : 'Tu Copiloto Legal',
          style: GoogleFonts.instrumentSerif(
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
          if (_showingDraft)
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
          else
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

    if (_showingDraft) {
      return _AnalysisBody(
        analysis: _draft!,
        isDraft: true,
        draftType: _draftType,
      );
    }

    final analysisAsync = ref.watch(contractAnalysisProvider(widget.propertyId));
    return analysisAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
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
              style: GoogleFonts.instrumentSerif(
                fontSize: 22,
                color: HitoTokens.ink1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Elegí el tipo de contrato. La IA arma una plantilla estándar '
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

  const _AnalysisBody({
    required this.analysis,
    required this.isDraft,
    this.draftType,
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
                    style: GoogleFonts.instrumentSerif(
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

class _HighlightedContractView extends StatelessWidget {
  final String contractText;
  final List<AnalyzedClause> clauses;
  const _HighlightedContractView({
    required this.contractText,
    required this.clauses,
  });

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

  List<TextSpan> _buildSpans() {
    final positions = <_Span>[];
    for (final clause in clauses) {
      final idx = contractText.indexOf(clause.clauseText);
      if (idx >= 0) {
        positions.add(_Span(
          start: idx,
          end: idx + clause.clauseText.length,
          clause: clause,
        ));
      }
    }
    positions.sort((a, b) => a.start.compareTo(b.start));

    final spans = <TextSpan>[];
    int cursor = 0;
    for (final pos in positions) {
      if (pos.start > cursor) {
        spans.add(TextSpan(text: contractText.substring(cursor, pos.start)));
      }
      spans.add(TextSpan(
        text: contractText.substring(pos.start, pos.end),
        style: TextStyle(
          backgroundColor: _bgFor(pos.clause.riskLevel),
          fontWeight: FontWeight.w500,
        ),
      ));
      cursor = pos.end;
    }
    if (cursor < contractText.length) {
      spans.add(TextSpan(text: contractText.substring(cursor)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
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
            children: _buildSpans(),
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
