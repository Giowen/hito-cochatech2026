import 'package:latlong2/latlong.dart';

/// Landmarks de Oruro usados como referencias en matching.
///
/// Coordenadas aproximadas verificadas en OSM. El LLM razona sobre
/// distancias reales (Haversine) entre estos puntos y cada propiedad,
/// no sobre tags simbólicos. Esto permite que el sistema responda
/// a queries como "cerca de la UTO" sin necesidad de etiquetar manualmente.
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
  // Universidades Oruro
  static const uto = Landmark(
    slug: 'uto',
    displayName: 'UTO (Universidad Técnica de Oruro)',
    coords: LatLng(-17.9560, -67.1010),
  );
  static const fni = Landmark(
    slug: 'fni',
    displayName: 'FNI (Facultad Nacional de Ingeniería)',
    coords: LatLng(-17.9688, -67.1142),
  );
  static const ucb = Landmark(
    slug: 'ucb',
    displayName: 'UCB (Universidad Católica Boliviana, Oruro)',
    coords: LatLng(-17.9735, -67.1095),
  );

  // Puntos comerciales, de oficina y servicios
  static const centroPlazaPrincipal = Landmark(
    slug: 'centro',
    displayName: 'Centro / Plaza 10 de Febrero',
    coords: LatLng(-17.9700, -67.1130),
  );
  static const mercadoFerminLopez = Landmark(
    slug: 'mercado',
    displayName: 'Mercado Fermín López (zona comercial)',
    coords: LatLng(-17.9690, -67.1180),
  );
  static const hospitalGeneral = Landmark(
    slug: 'hospital',
    displayName: 'Hospital General San Juan de Dios',
    coords: LatLng(-17.9712, -67.1182),
  );

  // Hitos culturales y deportivos
  static const santuarioSocavon = Landmark(
    slug: 'socavon',
    displayName: 'Santuario del Socavón',
    coords: LatLng(-17.9636, -67.1235),
  );
  static const faroConchupata = Landmark(
    slug: 'faro',
    displayName: 'Faro de Conchupata',
    coords: LatLng(-17.9810, -67.1140),
  );
  static const estadioBermudez = Landmark(
    slug: 'estadio',
    displayName: 'Estadio Jesús Bermúdez',
    coords: LatLng(-17.9745, -67.1075),
  );

  // Aeropuerto y terminal
  static const aeropuertoJuanMendoza = Landmark(
    slug: 'aeropuerto',
    displayName: 'Aeropuerto Juan Mendoza',
    coords: LatLng(-17.9626, -67.0762),
  );
  static const terminal = Landmark(
    slug: 'terminal',
    displayName: 'Terminal de Buses',
    coords: LatLng(-17.9582, -67.1140),
  );

  // Zonas / barrios de Oruro
  static const norte = Landmark(
    slug: 'norte',
    displayName: 'Zona Norte',
    coords: LatLng(-17.9520, -67.1100),
  );
  static const sud = Landmark(
    slug: 'sud',
    displayName: 'Zona Sud',
    coords: LatLng(-17.9890, -67.1150),
  );
  static const este = Landmark(
    slug: 'este',
    displayName: 'Zona Este',
    coords: LatLng(-17.9660, -67.0980),
  );
  static const laFloresta = Landmark(
    slug: 'la_floresta',
    displayName: 'La Floresta',
    coords: LatLng(-17.9760, -67.1050),
  );
  static const aguaDeCastilla = Landmark(
    slug: 'agua_de_castilla',
    displayName: 'Agua de Castilla',
    coords: LatLng(-17.9560, -67.1052),
  );
  static const sanJose = Landmark(
    slug: 'san_jose',
    displayName: 'San José',
    coords: LatLng(-17.9652, -67.1278),
  );
  static const villaEsperanza = Landmark(
    slug: 'villa_esperanza',
    displayName: 'Villa Esperanza',
    coords: LatLng(-17.9848, -67.1228),
  );
  static const lasKantutas = Landmark(
    slug: 'las_kantutas',
    displayName: 'Las Kantutas',
    coords: LatLng(-17.9555, -67.1180),
  );
  static const sebastianPagador = Landmark(
    slug: 'sebastian_pagador',
    displayName: 'Sebastián Pagador',
    coords: LatLng(-17.9898, -67.1083),
  );
  static const challacollo = Landmark(
    slug: 'challacollo',
    displayName: 'Villa Challacollo',
    coords: LatLng(-17.9928, -67.1198),
  );

  /// Todos los landmarks indexados por slug.
  static const Map<String, Landmark> bySlug = {
    'uto': uto,
    'fni': fni,
    'ucb': ucb,
    'centro': centroPlazaPrincipal,
    'mercado': mercadoFerminLopez,
    'hospital': hospitalGeneral,
    'socavon': santuarioSocavon,
    'faro': faroConchupata,
    'estadio': estadioBermudez,
    'aeropuerto': aeropuertoJuanMendoza,
    'terminal': terminal,
    'norte': norte,
    'sud': sud,
    'este': este,
    'la_floresta': laFloresta,
    'agua_de_castilla': aguaDeCastilla,
    'san_jose': sanJose,
    'villa_esperanza': villaEsperanza,
    'las_kantutas': lasKantutas,
    'sebastian_pagador': sebastianPagador,
    'challacollo': challacollo,
  };

  /// Lista de landmarks "principales" usados como contexto en el prompt
  /// de matching. Se prioriza relevancia para commute (estudio/trabajo/servicios).
  static const List<Landmark> matchingContext = [
    uto,
    fni,
    centroPlazaPrincipal,
    mercadoFerminLopez,
    hospitalGeneral,
  ];
}
