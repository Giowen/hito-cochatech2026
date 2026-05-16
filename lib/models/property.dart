import 'package:latlong2/latlong.dart';

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
  });

  LatLng get coords => LatLng(lat, lng);

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
      cochabambaTags: (json['cochabamba_tags'] as List).cast<String>(),
      listingStatus: json['listing_status'] as String,
      description: json['description'] as String,
      hasLien: json['has_lien'] as bool,
    );
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
      };
}
