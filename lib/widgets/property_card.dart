import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/match_result.dart';
import '../models/property.dart';
import '../providers.dart';
import '../theme.dart';

/// Wrapper que decide entre foto real (NetworkImage del Supabase Storage)
/// y placeholder gradient. Mantiene la API simple para los callers.
class _PropertyThumb extends StatelessWidget {
  final Property property;
  const _PropertyThumb({required this.property});

  @override
  Widget build(BuildContext context) {
    final photoUrl = property.photos.isNotEmpty ? property.photos.first : null;
    final isHttp = photoUrl != null && photoUrl.startsWith('http');
    final isAsset = photoUrl != null && photoUrl.startsWith('assets/');
    if (isHttp || isAsset) {
      final stub = _PhotoStub(image: property.image, type: property.type);
      return Container(
        width: 52,
        height: 52,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: HitoTokens.paper3,
          borderRadius: BorderRadius.circular(HitoTokens.rMd),
        ),
        child: isAsset
            ? Image.asset(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => stub,
              )
            : Image.network(
                photoUrl,
                fit: BoxFit.cover,
                // Si falla la carga (offline, cors, etc), caemos al gradient stub.
                errorBuilder: (_, __, ___) => stub,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return stub;
                },
              ),
      );
    }
    return _PhotoStub(image: property.image, type: property.type);
  }
}

/// PropertyCard compacta — claude-design canonical style.
/// Round teal compat badge + small photo stub + title/specs/price + ANTICRÉTICO chip.
class PropertyCard extends ConsumerWidget {
  final Property property;
  final MatchResult match;

  const PropertyCard({
    super.key,
    required this.property,
    required this.match,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedPropertyIdProvider);
    final isSelected = property.id == selectedId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () =>
              ref.read(selectedPropertyIdProvider.notifier).select(property.id),
          borderRadius: BorderRadius.circular(HitoTokens.rLg),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HitoTokens.paper,
              borderRadius: BorderRadius.circular(HitoTokens.rLg),
              border: Border.all(
                color: isSelected ? HitoTokens.teal : HitoTokens.border,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? const [
                      BoxShadow(
                        color: Color.fromRGBO(10, 124, 112, 0.12),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CompatBadge(score: match.compatibilityPercent),
                const SizedBox(width: 10),
                _PropertyThumb(property: property),
                const SizedBox(width: 12),
                Expanded(
                  child: _Details(property: property),
                ),
                if (property.supportsAnticretico) ...[
                  const SizedBox(width: 8),
                  const _AnticreticoChip(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompatBadge extends StatelessWidget {
  final int score;
  const _CompatBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = compatibilityColor(score);
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$score',
        style: GoogleFonts.geist(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _PhotoStub extends StatelessWidget {
  final String image;
  final String type;
  const _PhotoStub({required this.image, required this.type});

  /// 12 distinct gradients for visual differentiation
  /// (in production, replaced by real photos from R2).
  /// TODO R2: replace with NetworkImage from Cloudflare R2 signed URL.
  LinearGradient _gradientFor(String id) {
    final palettes = <List<Color>>[
      [const Color(0xFFE7E0CF), const Color(0xFFD8CDB1)],
      [const Color(0xFFE0E8E5), const Color(0xFFB8CFC4)],
      [const Color(0xFFEDE3D4), const Color(0xFFD9C7AC)],
      [const Color(0xFFDCE3EA), const Color(0xFFB7C5D5)],
      [const Color(0xFFE5E0D5), const Color(0xFFCBC1A8)],
      [const Color(0xFFE0DBD0), const Color(0xFFC2B89E)],
      [const Color(0xFFE2EAE5), const Color(0xFFBACFC6)],
      [const Color(0xFFEAE3D5), const Color(0xFFD0C2A6)],
      [const Color(0xFFDEE5EA), const Color(0xFFB8C8D8)],
      [const Color(0xFFE7E3D7), const Color(0xFFCBC0A8)],
      [const Color(0xFFE0E5D9), const Color(0xFFC0CCA8)],
      [const Color(0xFFEAE0D4), const Color(0xFFD2BFA5)],
    ];
    final idx = image.startsWith('gradient-')
        ? (int.tryParse(image.substring(9)) ?? 1) - 1
        : 0;
    return LinearGradient(
      colors: palettes[idx % palettes.length],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: _gradientFor(image),
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
      ),
      child: Icon(
        type == 'casa' ? Icons.home_outlined : Icons.apartment_outlined,
        size: 24,
        color: HitoTokens.ink3,
      ),
    );
  }
}

class _Details extends StatelessWidget {
  final Property property;
  const _Details({required this.property});

  String _neighborhoodLabel() {
    final n = property.neighborhood ?? '';
    if (n.isEmpty) return '';
    // Convert slug to title case
    return n
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final neighborhood = _neighborhoodLabel();
    final usdK = property.priceUsdParalelo > 0
        ? '\$${(property.priceUsdParalelo / 1000).toStringAsFixed(0)}k'
        : (property.anticreticoBob != null
            ? 'Bs ${(property.anticreticoBob! / 1000).toStringAsFixed(0)}k'
            : '—');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          property.displayTitle,
          style: GoogleFonts.geist(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: HitoTokens.ink1,
            height: 1.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          [
            if (neighborhood.isNotEmpty) neighborhood,
            '${property.bedrooms}d',
            '${property.bathrooms}b',
            '${property.areaM2}m²',
            if (property.parking > 0) '${property.parking}p',
          ].join(' · '),
          style: GoogleFonts.geist(
            fontSize: 11,
            color: HitoTokens.ink3,
          ),
        ),
        // Segunda línea de metadata: año + lote cuando hay data.
        if (property.yearBuilt != null || property.lotM2 != null) ...[
          const SizedBox(height: 1),
          Text(
            [
              if (property.yearBuilt != null) 'Año ${property.yearBuilt}',
              if (property.lotM2 != null) 'lote ${property.lotM2}m²',
            ].join(' · '),
            style: GoogleFonts.geist(
              fontSize: 10.5,
              color: HitoTokens.ink4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              usdK,
              style: GoogleFonts.geist(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: HitoTokens.ink1,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              property.priceUsdParalelo > 0 ? 'USD' : '',
              style: GoogleFonts.geist(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: HitoTokens.ink4,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AnticreticoChip extends StatelessWidget {
  const _AnticreticoChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFD7F0EA), // teal bg
        borderRadius: BorderRadius.circular(HitoTokens.rSm),
      ),
      child: Text(
        'ANTICRÉTICO',
        style: GoogleFonts.geist(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: HitoTokens.teal2,
        ),
      ),
    );
  }
}
