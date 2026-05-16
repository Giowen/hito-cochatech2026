import 'package:flutter/material.dart';
import '../models/match_result.dart';
import '../models/property.dart';

/// Card visual de una propiedad con match score, precio, specs y barra de compatibility.
class PropertyCard extends StatelessWidget {
  final Property property;
  final MatchResult match;
  final VoidCallback? onTap;

  const PropertyCard({
    super.key,
    required this.property,
    required this.match,
    this.onTap,
  });

  Color _bucketColor() {
    switch (match.colorBucket) {
      case 'green':
        return Colors.green.shade600;
      case 'amber':
        return Colors.orange.shade600;
      default:
        return Colors.grey.shade500;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bucketColor = _bucketColor();
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CoverImage(
              property: property,
              bucketColor: bucketColor,
              compatibility: match.compatibilityPercent,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.address,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${(property.priceBob / 1000).toStringAsFixed(0)}K Bs',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '· ~\$${(property.priceUsdParalelo / 1000).toStringAsFixed(0)}K USD paralelo',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _spec(context, Icons.bed_outlined, '${property.bedrooms}'),
                      const SizedBox(width: 16),
                      _spec(
                        context,
                        Icons.bathtub_outlined,
                        '${property.bathrooms}',
                      ),
                      const SizedBox(width: 16),
                      _spec(
                        context,
                        Icons.square_foot,
                        '${property.areaM2} m²',
                      ),
                      const Spacer(),
                      _ModeChip(mode: property.listingMode),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: match.compatibilityPercent / 100,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(bucketColor),
                      minHeight: 6,
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

  Widget _spec(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade700),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _CoverImage extends StatelessWidget {
  final Property property;
  final Color bucketColor;
  final int compatibility;

  const _CoverImage({
    required this.property,
    required this.bucketColor,
    required this.compatibility,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Container(
          height: 140,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primaryContainer,
                scheme.primary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Icon(
              property.type == 'casa' ? Icons.home : Icons.apartment,
              size: 64,
              color: scheme.onPrimary.withAlpha(120),
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bucketColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              '$compatibility% compatible',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String mode;
  const _ModeChip({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        mode,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
