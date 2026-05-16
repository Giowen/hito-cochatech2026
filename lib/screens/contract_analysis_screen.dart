import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contract_analysis.dart';
import '../providers.dart';

/// "Tu Copiloto Legal Inmobiliario" — Acto 3 del pitch.
/// Sprint 4.2: contract analysis con cláusulas coloreadas, gravamen alert,
/// summary AI, recomendaciones accionables.
class ContractAnalysisScreen extends ConsumerWidget {
  final String propertyId;
  const ContractAnalysisScreen({super.key, required this.propertyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisAsync = ref.watch(contractAnalysisProvider(propertyId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu Copiloto Legal'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      body: analysisAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error analizando contrato:\n$e'),
          ),
        ),
        data: (analysis) => _AnalysisBody(analysis: analysis),
      ),
    );
  }
}

class _AnalysisBody extends StatelessWidget {
  final ContractAnalysis analysis;
  const _AnalysisBody({required this.analysis});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ContractTypeHeader(
            contractType: analysis.contractType,
            riskScore: analysis.overallRiskScore,
          ),
          const SizedBox(height: 16),
          if (analysis.gravamenCheck.isFlagged) ...[
            _GravamenAlert(check: analysis.gravamenCheck),
            const SizedBox(height: 14),
          ],
          _AiSummary(text: analysis.summary),
          const SizedBox(height: 18),
          _SectionHeader(title: 'Contrato con análisis de cláusulas'),
          const SizedBox(height: 8),
          _HighlightedContract(
            contractText: analysis.contractText,
            clauses: analysis.analyzedClauses,
          ),
          const SizedBox(height: 18),
          _SectionHeader(title: 'Cláusulas analizadas (${analysis.analyzedClauses.length})'),
          const SizedBox(height: 8),
          for (final clause in analysis.analyzedClauses) ...[
            _ClauseCard(clause: clause),
            const SizedBox(height: 8),
          ],
          if (analysis.fraudPatternsDetected.isNotEmpty) ...[
            const SizedBox(height: 6),
            _SectionHeader(title: 'Patrones de fraude detectados'),
            const SizedBox(height: 6),
            for (final pattern in analysis.fraudPatternsDetected) ...[
              _BulletItem(
                icon: Icons.warning_amber,
                color: Colors.red.shade700,
                text: pattern,
              ),
            ],
          ],
          const SizedBox(height: 18),
          _SectionHeader(title: 'Recomendaciones accionables'),
          const SizedBox(height: 6),
          for (final rec in analysis.recommendations) ...[
            _BulletItem(
              icon: Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
              text: rec,
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Volver'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'PDF export — feature de Phase 5 polish'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf),
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

class _ContractTypeHeader extends StatelessWidget {
  final String contractType;
  final int riskScore;
  const _ContractTypeHeader({
    required this.contractType,
    required this.riskScore,
  });

  Color _riskColor() {
    if (riskScore >= 70) return Colors.red.shade700;
    if (riskScore >= 40) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  String _riskLabel() {
    if (riskScore >= 70) return 'RIESGO ALTO';
    if (riskScore >= 40) return 'RIESGO MEDIO';
    return 'RIESGO BAJO';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.gavel, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contrato de ${contractType[0].toUpperCase()}${contractType.substring(1)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  contractType == 'anticretico'
                      ? 'CC Bolivia arts. 1429-1438 (instrumento único)'
                      : 'Análisis legal automático',
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _riskColor(),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_riskLabel()}\n$riskScore/100',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
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
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade400, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.gpp_bad,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GRAVAMEN DETECTADO',
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  check.details,
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Consulta a Derechos Reales · ${DateTime.now().toString().substring(0, 10)}',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 10,
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

class _AiSummary extends StatelessWidget {
  final String text;
  const _AiSummary({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outline.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: scheme.primary, size: 18),
              const SizedBox(width: 6),
              Text(
                'AI análisis ejecutivo',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _HighlightedContract extends StatelessWidget {
  final String contractText;
  final List<AnalyzedClause> clauses;

  const _HighlightedContract({
    required this.contractText,
    required this.clauses,
  });

  Color _bgColorFor(RiskLevel level) {
    switch (level) {
      case RiskLevel.high:
        return const Color(0x55EF4444); // red.withAlpha(85)
      case RiskLevel.medium:
        return const Color(0x55F59E0B); // amber.withAlpha(85)
      case RiskLevel.low:
        return const Color(0x5510B981); // green.withAlpha(85)
    }
  }

  List<TextSpan> _buildSpans() {
    final positions = <_Position>[];
    for (final clause in clauses) {
      final idx = contractText.indexOf(clause.clauseText);
      if (idx >= 0) {
        positions.add(_Position(
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
          backgroundColor: _bgColorFor(pos.clause.riskLevel),
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
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(maxHeight: 380),
      child: SingleChildScrollView(
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 13,
              height: 1.6,
              fontFamily: 'monospace',
            ),
            children: _buildSpans(),
          ),
        ),
      ),
    );
  }
}

class _Position {
  final int start;
  final int end;
  final AnalyzedClause clause;
  _Position({required this.start, required this.end, required this.clause});
}

class _ClauseCard extends StatelessWidget {
  final AnalyzedClause clause;
  const _ClauseCard({required this.clause});

  Color _color() {
    switch (clause.riskLevel) {
      case RiskLevel.high:
        return Colors.red.shade600;
      case RiskLevel.medium:
        return Colors.orange.shade700;
      case RiskLevel.low:
        return Colors.green.shade700;
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
        return Icons.error;
      case RiskLevel.medium:
        return Icons.warning;
      case RiskLevel.low:
        return Icons.check_circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon(), size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                _label(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '"${clause.clauseText}"',
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (clause.issue.isNotEmpty) ...[
            const SizedBox(height: 8),
            _row(context, 'Problema:', clause.issue),
          ],
          if (clause.suggestion.isNotEmpty) ...[
            const SizedBox(height: 4),
            _row(context, 'Sugerencia:', clause.suggestion),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String text) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 12, height: 1.4),
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: text),
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
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
