import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/lead.dart';
import '../models/match_result.dart';
import '../models/property.dart';
import '../providers.dart';
import '../theme.dart';
import '../utils/tc_paralelo.dart';

/// Detalle de un lead: perfil estructurado + análisis AI de calificación
/// + matches recomendados del inventario propio + acciones del agente.
///
/// **Por qué importa**: el desafío exige automatizar la calificación. Acá
/// María ve por qué la AI clasificó al lead como hot/warm/cold y qué
/// matches específicos puede ofrecer. Sin esto, el inbox es solo una lista.
class LeadDetailScreen extends ConsumerStatefulWidget {
  final String leadId;
  const LeadDetailScreen({super.key, required this.leadId});

  @override
  ConsumerState<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends ConsumerState<LeadDetailScreen> {
  List<MatchResult>? _matches;
  bool _loadingMatches = true;
  String? _matchesError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMatches());
  }

  Future<void> _loadMatches() async {
    final leads = ref.read(leadsProvider).value ?? const [];
    final lead = leads.firstWhere(
      (l) => l.id == widget.leadId,
      orElse: () => throw StateError('Lead not found'),
    );
    final propertiesAsync = ref.read(propertiesProvider);
    final properties = propertiesAsync.value ?? const [];

    if (properties.isEmpty) {
      setState(() {
        _matches = const [];
        _loadingMatches = false;
      });
      return;
    }

    try {
      final svc = ref.read(matchingServiceProvider);
      final results = await svc.scoreAll(
        profile: lead.profile,
        properties: properties,
      );
      // Top 3 para el detalle — el agente quiere recomendaciones quirúrgicas,
      // no la lista completa.
      if (!mounted) return;
      setState(() {
        _matches = results.take(3).toList();
        _loadingMatches = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _matchesError = e.toString();
        _loadingMatches = false;
      });
    }
  }

  Future<void> _markContacted(Lead lead) async {
    await ref.read(leadsProvider.notifier).updateLead(
          lead.copyWith(
            status: LeadStatus.contacted,
            lastContactAt: DateTime.now(),
          ),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: HitoTokens.success,
        content: Text(
          'Lead marcado como contactado',
          style: GoogleFonts.geist(color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(Lead lead) async {
    final phone = lead.clientPhone?.replaceAll(RegExp(r'\D'), '');
    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: HitoTokens.warning,
          content: Text(
            'Este lead no tiene teléfono asociado.',
            style: GoogleFonts.geist(color: Colors.white),
          ),
        ),
      );
      return;
    }
    final firstName = (lead.clientName ?? '').split(' ').first;
    final greeting = firstName.isEmpty ? 'Hola' : 'Hola $firstName';
    final budgetUsd = TcParalelo.bobToUsd(lead.profile.budgetMax);
    final msg = '$greeting, soy María Quiroga de Hito. Vi tu búsqueda '
        '(${lead.profile.transactionType}, ${lead.profile.minBedrooms} dorm, '
        'hasta \$$budgetUsd USD) y tengo opciones que coinciden bien. '
        '¿Te llamo hoy a coordinar?';
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(msg)}',
    );
    // En Web abre nueva pestaña (LaunchMode.externalApplication == _blank).
    // En mobile abre la app de WhatsApp directamente si está instalada.
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: HitoTokens.danger,
          content: Text(
            'No se pudo abrir WhatsApp. ¿Está instalado / habilitado?',
            style: GoogleFonts.geist(color: Colors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(leadsProvider);
    final lead = leadsAsync.value?.firstWhere(
      (l) => l.id == widget.leadId,
      orElse: () => throw StateError('Lead not found'),
    );

    return Scaffold(
      backgroundColor: HitoTokens.bone,
      appBar: AppBar(
        backgroundColor: HitoTokens.bone,
        foregroundColor: HitoTokens.ink1,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Detalle del lead',
          style: hitoDisplay(
            fontSize: 22,
            color: HitoTokens.ink1,
          ),
        ),
      ),
      body: lead == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LeadHero(lead: lead),
                  const SizedBox(height: 16),
                  _ProfileCard(lead: lead),
                  const SizedBox(height: 14),
                  _QualificationCard(lead: lead),
                  const SizedBox(height: 14),
                  _MatchesSection(
                    matches: _matches,
                    loading: _loadingMatches,
                    error: _matchesError,
                  ),
                  const SizedBox(height: 20),
                  _ActionsBar(
                    lead: lead,
                    onContacted: () => _markContacted(lead),
                    onWhatsApp: () => _openWhatsApp(lead),
                  ),
                ],
              ),
            ),
    );
  }
}

class _LeadHero extends StatelessWidget {
  final Lead lead;
  const _LeadHero({required this.lead});

  Color _bucketColor() {
    switch (lead.bucket) {
      case LeadBucket.hot:
        return HitoTokens.danger;
      case LeadBucket.warm:
        return HitoTokens.warning;
      case LeadBucket.cold:
        return HitoTokens.ink4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _bucketColor();
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
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HitoTokens.teal,
              shape: BoxShape.circle,
            ),
            child: Text(
              lead.initials,
              style: GoogleFonts.geist(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lead.clientName ?? 'Lead sin nombre',
                  style: GoogleFonts.geist(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: HitoTokens.ink1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lead.clientPhone ?? 'Sin teléfono · ${lead.source.label}',
                  style: GoogleFonts.geist(
                    fontSize: 11.5,
                    color: HitoTokens.ink3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius:
                            BorderRadius.circular(HitoTokens.rSm),
                      ),
                      child: Text(
                        '${lead.bucket.label} · ${lead.qualificationScore}/100',
                        style: GoogleFonts.geist(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      lead.ageLabel,
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        color: HitoTokens.ink4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Lead lead;
  const _ProfileCard({required this.lead});

  @override
  Widget build(BuildContext context) {
    final p = lead.profile;
    final budgetUsd = TcParalelo.bobToUsd(p.budgetMax);
    final hasLocation = p.radiusKm < 50;

    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 14, color: HitoTokens.ink3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.geist(
                    fontSize: 12.5,
                    color: HitoTokens.ink1,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HitoTokens.paper,
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('PERFIL ESTRUCTURADO POR AI'),
          const SizedBox(height: 8),
          if (p.voiceInputTranscript != null &&
              p.voiceInputTranscript!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: HitoTokens.paper2,
                borderRadius: BorderRadius.circular(HitoTokens.rMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote, size: 14, color: HitoTokens.ink4),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      p.voiceInputTranscript!,
                      style: GoogleFonts.geist(
                        fontSize: 11.5,
                        color: HitoTokens.ink2,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          row(Icons.attach_money,
              'Presupuesto: hasta \$$budgetUsd USD (${p.transactionType})'),
          row(Icons.king_bed_outlined,
              'Mínimo ${p.minBedrooms} dorm · ${p.minAreaM2}+ m²'),
          if (hasLocation)
            row(Icons.location_on_outlined,
                'Radio ${p.radiusKm.toStringAsFixed(1)} km de '
                '${p.desiredLat.toStringAsFixed(3)}, ${p.desiredLng.toStringAsFixed(3)}')
          else
            row(Icons.public, 'Sin preferencia de ubicación específica'),
          if (p.requiredTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: p.requiredTags
                    .map((t) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: HitoTokens.paper2,
                            borderRadius:
                                BorderRadius.circular(HitoTokens.rSm),
                          ),
                          child: Text(
                            t.replaceAll('_', ' '),
                            style: GoogleFonts.geist(
                              fontSize: 10,
                              color: HitoTokens.ink2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _QualificationCard extends StatelessWidget {
  final Lead lead;
  const _QualificationCard({required this.lead});

  @override
  Widget build(BuildContext context) {
    final color = switch (lead.bucket) {
      LeadBucket.hot => HitoTokens.danger,
      LeadBucket.warm => HitoTokens.warning,
      LeadBucket.cold => HitoTokens.ink4,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                'ANÁLISIS AI DE CALIFICACIÓN',
                style: GoogleFonts.geist(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (lead.qualificationReasoning.isEmpty)
            Text(
              'Sin razones registradas — el LLM no devolvió detalle.',
              style: GoogleFonts.geist(
                fontSize: 12,
                color: HitoTokens.ink3,
              ),
            )
          else
            for (final reason in lead.qualificationReasoning)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        reason,
                        style: GoogleFonts.geist(
                          fontSize: 12.5,
                          color: HitoTokens.ink1,
                          height: 1.5,
                        ),
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

class _MatchesSection extends ConsumerWidget {
  final List<MatchResult>? matches;
  final bool loading;
  final String? error;
  const _MatchesSection({
    required this.matches,
    required this.loading,
    required this.error,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider).value ?? const [];
    final propMap = {for (final p in properties) p.id: p};

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HitoTokens.paper,
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('TOP 3 MATCHES DE TU INVENTARIO'),
          const SizedBox(height: 10),
          if (loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Calculando matches con tu inventario...',
                    style: GoogleFonts.geist(
                      fontSize: 12,
                      color: HitoTokens.ink3,
                    ),
                  ),
                ],
              ),
            )
          else if (error != null)
            Text(
              'Error: $error',
              style: GoogleFonts.geist(fontSize: 12, color: HitoTokens.danger),
            )
          else if (matches == null || matches!.isEmpty)
            Text(
              'Sin matches en tu inventario actual para este perfil.',
              style: GoogleFonts.geist(
                fontSize: 12,
                color: HitoTokens.ink3,
              ),
            )
          else
            for (final m in matches!) _MatchMiniCard(match: m, property: propMap[m.propertyId]),
        ],
      ),
    );
  }
}

class _MatchMiniCard extends StatelessWidget {
  final MatchResult match;
  final Property? property;
  const _MatchMiniCard({required this.match, required this.property});

  @override
  Widget build(BuildContext context) {
    if (property == null) return const SizedBox.shrink();
    final p = property!;
    final color = compatibilityColor(match.compatibilityPercent);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: HitoTokens.paper2,
          borderRadius: BorderRadius.circular(HitoTokens.rMd),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(
                '${match.compatibilityPercent}',
                style: GoogleFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title ?? p.address,
                    style: GoogleFonts.geist(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: HitoTokens.ink1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${p.bedrooms}d · ${p.areaM2}m² · \$${p.priceUsdParalelo ~/ 1000}k',
                    style: GoogleFonts.geist(
                      fontSize: 10.5,
                      color: HitoTokens.ink3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionsBar extends StatelessWidget {
  final Lead lead;
  final VoidCallback onContacted;
  final VoidCallback onWhatsApp;
  const _ActionsBar({
    required this.lead,
    required this.onContacted,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: lead.status == LeadStatus.pending ? onContacted : null,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(
              lead.status == LeadStatus.pending
                  ? 'Marcar contactado'
                  : 'Ya contactado',
              style: GoogleFonts.geist(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: onWhatsApp,
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: Text(
              'Abrir WhatsApp',
              style: GoogleFonts.geist(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
            ),
          ),
        ),
      ],
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
        fontWeight: FontWeight.w700,
        color: HitoTokens.ink4,
      ),
    );
  }
}
