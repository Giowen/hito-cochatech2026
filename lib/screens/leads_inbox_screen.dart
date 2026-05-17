import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/lead.dart';
import '../providers.dart';
import '../theme.dart';
import 'lead_detail_screen.dart';

/// Inbox de leads del agente — pantalla principal cuando viewMode=agent.
///
/// **Por qué es importante**: el desafío exige "automatizar la calificación
/// de clientes". Esta pantalla resuelve exactamente eso: María entra y ve
/// quiénes son sus leads, en qué temperatura, priorizados por score AI.
///
/// Layout: header con counters → filtros temperatura → lista de cards.
class LeadsInboxScreen extends ConsumerStatefulWidget {
  const LeadsInboxScreen({super.key});

  @override
  ConsumerState<LeadsInboxScreen> createState() => _LeadsInboxScreenState();
}

enum _LeadFilter { all, hot, warm, cold, pending }

class _LeadsInboxScreenState extends ConsumerState<LeadsInboxScreen> {
  _LeadFilter _filter = _LeadFilter.all;

  List<Lead> _applyFilter(List<Lead> leads) {
    switch (_filter) {
      case _LeadFilter.all:
        return leads;
      case _LeadFilter.hot:
        return leads.where((l) => l.bucket == LeadBucket.hot).toList();
      case _LeadFilter.warm:
        return leads.where((l) => l.bucket == LeadBucket.warm).toList();
      case _LeadFilter.cold:
        return leads.where((l) => l.bucket == LeadBucket.cold).toList();
      case _LeadFilter.pending:
        return leads.where((l) => l.status == LeadStatus.pending).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(leadsProvider);
    // El back solo aplica si esta pantalla se pusheó arriba de otra
    // (ej. desde el sidebar). Si está embebida en el shell principal con
    // el sidebar visible, canPop = false y no mostramos botón.
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: HitoTokens.bone,
      appBar: canPop
          ? AppBar(
              backgroundColor: HitoTokens.bone,
              foregroundColor: HitoTokens.ink1,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Volver',
                onPressed: () => Navigator.of(context).pop(),
              ),
              titleSpacing: 0,
              title: Text(
                'Inbox de leads',
                style: hitoDisplay(
                  fontSize: 22,
                  color: HitoTokens.ink1,
                  height: 1.0,
                ),
              ),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // El header grande solo cuando no hay AppBar (caso embebido).
          if (!canPop) _InboxHeader(),
          if (!canPop) const SizedBox(height: 8),
          if (canPop) const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _FilterChips(
              current: _filter,
              onChange: (f) => setState(() => _filter = f),
              leads: leadsAsync.value ?? const [],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: leadsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (leads) {
                final filtered = _applyFilter(leads);
                if (filtered.isEmpty) {
                  return _EmptyLeadsState(filter: _filter);
                }
                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _LeadCard(
                    lead: filtered[i],
                    onTap: () {
                      ref
                          .read(selectedLeadIdProvider.notifier)
                          .select(filtered[i].id);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              LeadDetailScreen(leadId: filtered[i].id),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider).value ?? const [];
    final hot = leads.where((l) => l.bucket == LeadBucket.hot).length;
    final warm = leads.where((l) => l.bucket == LeadBucket.warm).length;
    final pending = leads.where((l) => l.status == LeadStatus.pending).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inbox de leads',
                  style: hitoDisplay(
                    fontSize: 28,
                    color: HitoTokens.ink1,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$pending pendientes · $hot calientes · $warm tibios',
                  style: GoogleFonts.geist(
                    fontSize: 12,
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

class _FilterChips extends StatelessWidget {
  final _LeadFilter current;
  final ValueChanged<_LeadFilter> onChange;
  final List<Lead> leads;

  const _FilterChips({
    required this.current,
    required this.onChange,
    required this.leads,
  });

  @override
  Widget build(BuildContext context) {
    final hot = leads.where((l) => l.bucket == LeadBucket.hot).length;
    final warm = leads.where((l) => l.bucket == LeadBucket.warm).length;
    final cold = leads.where((l) => l.bucket == LeadBucket.cold).length;
    final pending = leads.where((l) => l.status == LeadStatus.pending).length;

    Widget chip(_LeadFilter f, String label, int? count, Color color) {
      final active = current == f;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(HitoTokens.r2xl),
            onTap: () => onChange(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? color : HitoTokens.paper,
                border: Border.all(
                  color: active ? color : HitoTokens.border,
                ),
                borderRadius: BorderRadius.circular(HitoTokens.r2xl),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.geist(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : HitoTokens.ink2,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white.withAlpha(60)
                            : HitoTokens.paper2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: GoogleFonts.geist(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : HitoTokens.ink3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(_LeadFilter.all, 'Todos', leads.length, HitoTokens.ink2),
          chip(_LeadFilter.pending, 'Pendientes', pending, HitoTokens.navy),
          chip(_LeadFilter.hot, 'Calientes', hot, HitoTokens.danger),
          chip(_LeadFilter.warm, 'Tibios', warm, HitoTokens.warning),
          chip(_LeadFilter.cold, 'Fríos', cold, HitoTokens.ink4),
        ],
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  final Lead lead;
  final VoidCallback onTap;
  const _LeadCard({required this.lead, required this.onTap});

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

  Color _avatarColor() {
    // Determinístico por id — el mismo lead siempre obtiene el mismo color.
    final hash = lead.id.hashCode.abs();
    const palette = [
      Color(0xFF0A7C70),
      Color(0xFF0D2C54),
      Color(0xFFB8893D),
      Color(0xFF4A9D57),
      Color(0xFFC2790A),
      Color(0xFF1A4480),
    ];
    return palette[hash % palette.length];
  }

  String _summary() {
    final tx = lead.profile.transactionType;
    final dorm = lead.profile.minBedrooms;
    final budgetK =
        (lead.profile.budgetMax / 1000 / 12.20).round(); // BOB→USD k
    final tags = lead.profile.requiredTags;
    return [
      tx,
      '${dorm}d+',
      'hasta \$${budgetK}k',
      if (tags.isNotEmpty) tags.take(2).join('+'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final color = _bucketColor();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HitoTokens.rLg),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HitoTokens.paper,
              borderRadius: BorderRadius.circular(HitoTokens.rLg),
              border: Border.all(
                color: lead.status == LeadStatus.pending
                    ? HitoTokens.border
                    : HitoTokens.border.withAlpha(120),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar circular
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _avatarColor(),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        lead.initials,
                        style: GoogleFonts.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Mini badge de fuente
                    if (lead.source == LeadSource.shareLink)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: HitoTokens.teal,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: HitoTokens.paper, width: 2),
                          ),
                          child: const Icon(Icons.link,
                              size: 9, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lead.clientName ?? 'Lead sin nombre',
                              style: GoogleFonts.geist(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: HitoTokens.ink1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius:
                                  BorderRadius.circular(HitoTokens.rSm),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  lead.bucket.label,
                                  style: GoogleFonts.geist(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${lead.qualificationScore}',
                                  style: GoogleFonts.geist(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _summary(),
                        style: GoogleFonts.geist(
                          fontSize: 11.5,
                          color: HitoTokens.ink3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.schedule,
                              size: 10, color: HitoTokens.ink4),
                          const SizedBox(width: 4),
                          Text(
                            lead.ageLabel,
                            style: GoogleFonts.geist(
                              fontSize: 10.5,
                              color: HitoTokens.ink4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: HitoTokens.paper2,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              lead.status.label,
                              style: GoogleFonts.geist(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: HitoTokens.ink3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLeadsState extends StatelessWidget {
  final _LeadFilter filter;
  const _EmptyLeadsState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      _LeadFilter.all => 'Tu inbox está vacío',
      _LeadFilter.hot => 'No hay leads calientes',
      _LeadFilter.warm => 'No hay leads tibios',
      _LeadFilter.cold => 'No hay leads fríos',
      _LeadFilter.pending => 'No hay leads pendientes',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: HitoTokens.ink4),
            const SizedBox(height: 12),
            Text(
              label,
              style: hitoDisplay(
                fontSize: 18,
                color: HitoTokens.ink2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Comparte tu link con clientes desde el botón "Mi link" arriba.',
              textAlign: TextAlign.center,
              style: GoogleFonts.geist(
                fontSize: 12,
                color: HitoTokens.ink4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
