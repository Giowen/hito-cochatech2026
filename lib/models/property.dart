import 'package:latlong2/latlong.dart';

import '../utils/distance.dart';
import '../utils/landmarks.dart';

/// Property model — listing inmobiliario de Cochabamba.
/// Spec en PRD §6 y hardcoded demo path en PITCH_PREP §3.
class Property {
  final String id;
  final String address;
  final double lat;
  final double lng;
  final int priceBob;
  final int priceUsdParalelo;
  final int areaM2;
  final int bedrooms;
  final int bathrooms;
  final String type; // casa | departamento | terreno
  final String listingMode; // venta | alquiler | anticretico
  final List<String> amenities;
  final int ageYears;
  final List<String> photos;
  final List<String> cochabambaTags;
  final String listingStatus;
  final String description;
  final bool hasLien;

  // ── Claude-design canonical fields (Phase A.2) ─────────────
  /// Display title, fallback to address.
  final String? title;

  /// Neighborhood slug (e.g. 'cala_cala', 'recoleta').
  final String? neighborhood;

  /// Parking spots (vehicles).
  final int parking;

  /// Lot size in m² (terreno), distinct from area_m2 (construido).
  final int? lotM2;

  /// All transaction modes supported (e.g. ['venta', 'anticretico']).
  final List<String> supportedTransactions;

  /// Anticretico amount in BOB (if applicable).
  final int? anticreticoBob;

  /// Year of construction.
  final int? yearBuilt;

  /// Pre-computed AI reasoning notes for demo path consistency.
  final List<String> aiNotes;

  /// Cached compatibility score for demo path (avoids LLM call latency).
  final int? compatibility;

  /// Days since listing.
  final int listedDays;

  /// Agent assigned to this listing.
  final String? agentName;

  /// Gradient/image identifier for visual differentiation.
  final String image;

  const Property({
    required this.id,
    required this.address,
    required this.lat,
    required this.lng,
    required this.priceBob,
    required this.priceUsdParalelo,
    required this.areaM2,
    required this.bedrooms,
    required this.bathrooms,
    required this.type,
    required this.listingMode,
    required this.amenities,
    required this.ageYears,
    required this.photos,
    required this.cochabambaTags,
    required this.listingStatus,
    required this.description,
    required this.hasLien,
    this.title,
    this.neighborhood,
    this.parking = 0,
    this.lotM2,
    this.supportedTransactions = const [],
    this.anticreticoBob,
    this.yearBuilt,
    this.aiNotes = const [],
    this.compatibility,
    this.listedDays = 0,
    this.agentName,
    this.image = 'gradient-1',
  });

  LatLng get coords => LatLng(lat, lng);

  /// Distancia Haversine en km desde esta propiedad a otra coordenada.
  double distanceToKm(LatLng other) => haversineKm(coords, other);

  /// Distancias a los landmarks principales (UMSS, UPB, UCB, Recoleta, Centro).
  /// Devuelve `{slug: km}` con 2 decimales. Usado como contexto cuantitativo
  /// del LLM en el prompt de scoring.
  Map<String, double> get distancesToLandmarks {
    return {
      for (final l in Landmarks.matchingContext)
        l.slug: double.parse(distanceToKm(l.coords).toStringAsFixed(2)),
    };
  }

  factory Property.fromJson(Map<String, dynamic> json) {
    return Property(
      id: json['id'] as String,
      address: json['address'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      priceBob: json['price_bob'] as int,
      priceUsdParalelo: json['price_usd_paralelo'] as int,
      areaM2: json['area_m2'] as int,
      bedrooms: json['bedrooms'] as int,
      bathrooms: json['bathrooms'] as int,
      type: json['type'] as String,
      listingMode: json['listing_mode'] as String,
      amenities: (json['amenities'] as List).cast<String>(),
      ageYears: json['age_years'] as int,
      photos: (json['photos'] as List).cast<String>(),
      cochabambaTags:
          (json['cochabamba_tags'] as List? ?? const []).cast<String>(),
      listingStatus: json['listing_status'] as String? ?? 'activa',
      description: json['description'] as String? ?? '',
      hasLien: json['has_lien'] as bool? ?? false,
      title: json['title'] as String?,
      neighborhood: json['neighborhood'] as String?,
      parking: json['parking'] as int? ?? 0,
      lotM2: json['lot_m2'] as int?,
      supportedTransactions: (json['supported_transactions'] as List?
              ?? [json['listing_mode'] as String])
          .cast<String>(),
      anticreticoBob: json['anticretico_bob'] as int?,
      yearBuilt: json['year_built'] as int?,
      aiNotes: (json['ai_notes'] as List? ?? const []).cast<String>(),
      compatibility: json['compatibility'] as int?,
      listedDays: json['listed_days'] as int? ?? 0,
      agentName: json['agent_name'] as String?,
      image: json['image'] as String? ?? 'gradient-1',
    );
  }

  /// Display name — title si está, address como fallback.
  String get displayTitle => title ?? address;

  /// True si esta propiedad admite anticrético como modalidad.
  bool get supportsAnticretico =>
      supportedTransactions.contains('anticretico') ||
      listingMode == 'anticretico' ||
      anticreticoBob != null;

  /// Precio efectivo en BOB según la modalidad de transacción.
  /// - 'anticretico' → anticreticoBob (capital de anticrético)
  /// - 'venta' / 'compra' / otros → priceBob (precio de venta)
  /// - alquiler u otros sin valor → 0
  ///
  /// Crítico para budget comparisons: para anticrético, el cliente piensa en
  /// el capital ~$20-40k USD, no en el priceBob ~$200k USD.
  int effectivePriceBob(String transactionType) {
    if (transactionType == 'anticretico' && anticreticoBob != null) {
      return anticreticoBob!;
    }
    return priceBob;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'address': address,
        'lat': lat,
        'lng': lng,
        'price_bob': priceBob,
        'price_usd_paralelo': priceUsdParalelo,
        'area_m2': areaM2,
        'bedrooms': bedrooms,
        'bathrooms': bathrooms,
        'type': type,
        'listing_mode': listingMode,
        'amenities': amenities,
        'age_years': ageYears,
        'photos': photos,
        'cochabamba_tags': cochabambaTags,
        'listing_status': listingStatus,
        'description': description,
        'has_lien': hasLien,
        if (title != null) 'title': title,
        if (neighborhood != null) 'neighborhood': neighborhood,
        'parking': parking,
        if (lotM2 != null) 'lot_m2': lotM2,
        'supported_transactions': supportedTransactions,
        if (anticreticoBob != null) 'anticretico_bob': anticreticoBob,
        if (yearBuilt != null) 'year_built': yearBuilt,
        'ai_notes': aiNotes,
        if (compatibility != null) 'compatibility': compatibility,
        'listed_days': listedDays,
        if (agentName != null) 'agent_name': agentName,
        'image': image,
      };
}
