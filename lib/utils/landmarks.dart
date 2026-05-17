import 'package:latlong2/latlong.dart';

/// Landmarks de Cochabamba usados como referencias en matching.
///
/// Coordenadas aproximadas verificadas en OSM. El LLM razona sobre
/// distancias reales (Haversine) entre estos puntos y cada propiedad,
/// no sobre tags simbólicos. Esto permite que el sistema responda
/// a queries como "cerca de UMSS" sin necesidad de etiquetar manualmente.
class Landmark {
  final String slug;
  final String displayName;
  final LatLng coords;

  const Landmark({
    required this.slug,
    required this.displayName,
    required this.coords,
  });
}

class Landmarks {
  // Universidades Cochabamba
  static const umss = Landmark(
    slug: 'umss',
    displayName: 'UMSS (Universidad Mayor de San Simón)',
    coords: LatLng(-17.3935, -66.1480),
  );
  static const upb = Landmark(
    slug: 'upb',
    displayName: 'UPB (Universidad Privada Boliviana)',
    coords: LatLng(-17.3796, -66.1465),
  );
  static const ucb = Landmark(
    slug: 'ucb',
    displayName: 'UCB (Universidad Católica)',
    coords: LatLng(-17.3818, -66.1539),
  );
  static const univalle = Landmark(
    slug: 'univalle',
    displayName: 'Univalle',
    coords: LatLng(-17.4031, -66.1640),
  );

  // Sucre (otra ciudad, referencia para queries cross-ciudad)
  static const umsfx = Landmark(
    slug: 'umsfx',
    displayName: 'UMSFX (Universidad Mayor de San Francisco Xavier, Sucre)',
    coords: LatLng(-19.0419, -65.2598),
  );

  // Puntos comerciales y de oficina
  static const recoletaOffice = Landmark(
    slug: 'recoleta',
    displayName: 'Recoleta (zona oficina)',
    coords: LatLng(-17.3760, -66.1400),
  );
  static const centroPlazaPrincipal = Landmark(
    slug: 'centro',
    displayName: 'Centro / Plaza 14 de Septiembre',
    coords: LatLng(-17.3935, -66.1570),
  );
  static const calaCala = Landmark(
    slug: 'cala_cala',
    displayName: 'Cala Cala',
    coords: LatLng(-17.3815, -66.1623),
  );
  static const queruQueru = Landmark(
    slug: 'queru_queru',
    displayName: 'Queru Queru',
    coords: LatLng(-17.3712, -66.1492),
  );
  static const sarco = Landmark(
    slug: 'sarco',
    displayName: 'Sarco',
    coords: LatLng(-17.3690, -66.1758),
  );
  static const tupuraya = Landmark(
    slug: 'tupuraya',
    displayName: 'Tupuraya',
    coords: LatLng(-17.3950, -66.1280),
  );

  // Aeropuerto y terminal
  static const jorgeWilstermann = Landmark(
    slug: 'aeropuerto',
    displayName: 'Aeropuerto Jorge Wilstermann',
    coords: LatLng(-17.4211, -66.1771),
  );

  // Zonas adicionales Cochabamba
  static const albarrancho = Landmark(
    slug: 'albarrancho',
    displayName: 'Albarrancho',
    coords: LatLng(-17.4317, -66.1969),
  );
  static const villaBusch = Landmark(
    slug: 'villa_busch',
    displayName: 'Villa Busch',
    coords: LatLng(-17.418, -66.135),
  );
  static const pacataAlta = Landmark(
    slug: 'pacata',
    displayName: 'Pacata Alta',
    coords: LatLng(-17.420, -66.170),
  );
  static const tiquipaya = Landmark(
    slug: 'tiquipaya',
    displayName: 'Tiquipaya',
    coords: LatLng(-17.337, -66.207),
  );
  static const sacaba = Landmark(
    slug: 'sacaba',
    displayName: 'Sacaba',
    coords: LatLng(-17.398, -66.040),
  );
  static const vinto = Landmark(
    slug: 'vinto',
    displayName: 'Vinto',
    coords: LatLng(-17.378, -66.310),
  );
  static const colcapirhua = Landmark(
    slug: 'colcapirhua',
    displayName: 'Colcapirhua',
    coords: LatLng(-17.380, -66.218),
  );
  static const quillacollo = Landmark(
    slug: 'quillacollo',
    displayName: 'Quillacollo',
    coords: LatLng(-17.395, -66.275),
  );
  static const cochabambaNorte = Landmark(
    slug: 'cocha_norte',
    displayName: 'Cocha Norte / Las Palmas',
    coords: LatLng(-17.358, -66.140),
  );

  /// Todos los landmarks indexados por slug.
  static const Map<String, Landmark> bySlug = {
    'umss': umss,
    'upb': upb,
    'ucb': ucb,
    'univalle': univalle,
    'umsfx': umsfx,
    'recoleta': recoletaOffice,
    'centro': centroPlazaPrincipal,
    'cala_cala': calaCala,
    'queru_queru': queruQueru,
    'sarco': sarco,
    'tupuraya': tupuraya,
    'aeropuerto': jorgeWilstermann,
    'albarrancho': albarrancho,
    'villa_busch': villaBusch,
    'pacata': pacataAlta,
    'tiquipaya': tiquipaya,
    'sacaba': sacaba,
    'vinto': vinto,
    'colcapirhua': colcapirhua,
    'quillacollo': quillacollo,
    'cocha_norte': cochabambaNorte,
  };

  /// Lista de landmarks "principales" usados como contexto en el prompt
  /// de matching. Se prioriza relevancia (no incluir Sucre/aeropuerto).
  static const List<Landmark> matchingContext = [
    umss,
    upb,
    ucb,
    recoletaOffice,
    centroPlazaPrincipal,
  ];
}
