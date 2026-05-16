import 'dart:math';

import 'package:latlong2/latlong.dart';

/// Haversine distance entre dos coordenadas en km.
/// Earth radius = 6371.0088 km (mean). Resultado en km decimal.
double haversineKm(LatLng a, LatLng b) {
  const earthRadiusKm = 6371.0088;
  final dLat = _deg2rad(b.latitude - a.latitude);
  final dLon = _deg2rad(b.longitude - a.longitude);
  final lat1 = _deg2rad(a.latitude);
  final lat2 = _deg2rad(b.latitude);

  final h = sin(dLat / 2) * sin(dLat / 2) +
      sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
  final c = 2 * atan2(sqrt(h), sqrt(1 - h));
  return earthRadiusKm * c;
}

double _deg2rad(double d) => d * pi / 180.0;

/// Tiempo en minutos aproximado caminando/auto en ciudad.
/// 3 min/km es razonable para auto urbano con tráfico medio.
int minutesByCarKm(double km) => (km * 3).round();

/// Formato display "1.2 km · 4 min auto".
String formatDistance(double km) {
  final m = minutesByCarKm(km);
  if (km < 1.0) {
    final meters = (km * 1000).round();
    return '$meters m · $m min auto';
  }
  return '${km.toStringAsFixed(1)} km · $m min auto';
}
