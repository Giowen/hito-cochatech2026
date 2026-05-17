import 'dart:math' as math;

import '../models/client_profile.dart';
import '../models/property.dart';

/// PropertyPreFilter — algoritmo determinístico que descarta y rankea
/// propiedades ANTES de mandarlas al LLM.
///
/// **Por qué pre-filtrar**:
///   1. Reduce Groq calls de N → top N_KEEP (default 6) → menos rate limit.
///   2. Hard filters elimina propiedades que NO pueden ser matches (modalidad
///      incompatible, tipo distinto, bedrooms insuficientes).
///   3. Scoring heurístico ordena las restantes por proximidad de
///      presupuesto/distancia/dorms — el LLM scorea sólo los más prometedores.
///
/// **Qué NO hace**: el LLM aún hace el scoring final + explanation. Este filtro
/// es estructural, no semántico.
class PropertyPreFilter {
  /// Cuántas propiedades pasan al LLM. Si el inventario es <= max, todas pasan.
  final int maxResults;

  const PropertyPreFilter({this.maxResults = 6});

  /// Filtra hard requirements + rankea heurísticamente + take top N.
  List<Property> apply(ClientProfile profile, List<Property> all) {
    final filtered = all.where((p) => _passesHardFilter(profile, p)).toList();

    if (filtered.length <= maxResults) {
      filtered.sort(
        (a, b) => _heuristicScore(profile, b)
            .compareTo(_heuristicScore(profile, a)),
      );
      return filtered;
    }

    filtered.sort(
      (a, b) => _heuristicScore(profile, b)
          .compareTo(_heuristicScore(profile, a)),
    );
    return filtered.take(maxResults).toList();
  }

  /// Hard filters — propiedad descartada si no cumple alguno.
  bool _passesHardFilter(ClientProfile profile, Property property) {
    // Modalidad: 'compra' del cliente equivale a 'venta' de la propiedad.
    final wanted = profile.transactionType == 'compra'
        ? 'venta'
        : profile.transactionType;
    final supports = property.supportedTransactions.isNotEmpty
        ? property.supportedTransactions
        : [property.listingMode];
    if (!supports.contains(wanted)) return false;

    // Tipo de propiedad — lee voiceInputTranscript para detectar preferencia.
    // Si el cliente NO mencionó tipo, todas pasan. Si mencionó depto explícito,
    // descartar casa/terreno. Etc.
    final transcript =
        (profile.voiceInputTranscript ?? '').toLowerCase();
    final wantsDepto = _mentionsAny(
      transcript,
      ['departamento', 'depto', 'edificio', 'apartamento'],
    );
    final wantsCasa = !wantsDepto &&
        _mentionsAny(transcript, ['casa', 'vivienda familiar']);
    final wantsTerreno =
        _mentionsAny(transcript, ['terreno', 'lote', 'parcela']);

    if (wantsTerreno && property.type != 'terreno') return false;
    if (wantsDepto && property.type != 'departamento') return false;
    if (wantsCasa && property.type != 'casa') return false;

    // Bedrooms — mínimo absoluto si el cliente lo pidió.
    if (profile.minBedrooms > 0 &&
        property.bedrooms < profile.minBedrooms) {
      return false;
    }

    return true;
  }

  /// Score heurístico 0-100, usado para rankear pre-LLM.
  /// NO es el score final que ve el usuario (eso es del LLM con caps).
  double _heuristicScore(ClientProfile profile, Property property) {
    var score = 0.0;

    // Budget fit (40 pts) — usa effectivePriceBob según modalidad
    final effectivePrice =
        property.effectivePriceBob(profile.transactionType);
    if (profile.budgetMax > 0 && effectivePrice > 0) {
      if (effectivePrice >= profile.budgetMin &&
          effectivePrice <= profile.budgetMax) {
        score += 40;
      } else if (effectivePrice > profile.budgetMax) {
        final excess =
            (effectivePrice - profile.budgetMax) / profile.budgetMax;
        score += math.max(0, 40 - excess * 60);
      } else {
        score += 30;
      }
    } else {
      score += 20;
    }

    // Distance (30 pts) — sólo aplica si user especificó ubicación.
    // Si radius >= 50 (sentinel), full points (sin penalización geográfica).
    if (profile.radiusKm < 50) {
      final dKm = property.distanceToKm(profile.desiredLocation);
      final radius =
          profile.radiusKm > 0 ? profile.radiusKm : 3.0;
      score += math.max(0, 30 - (dKm / radius) * 20);
    } else {
      score += 25; // neutral — no penalizar
    }

    // Bedrooms exact match (15 pts)
    if (property.bedrooms == profile.minBedrooms) {
      score += 15;
    } else if (property.bedrooms == profile.minBedrooms + 1) {
      score += 10;
    } else if (property.bedrooms > profile.minBedrooms) {
      score += 5;
    }

    // Tags overlap (15 pts)
    final tagsMatched = profile.requiredTags
        .where((t) => property.cochabambaTags.contains(t))
        .length;
    if (profile.requiredTags.isNotEmpty) {
      score += (tagsMatched / profile.requiredTags.length) * 15;
    }

    return score;
  }

  bool _mentionsAny(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }
}
