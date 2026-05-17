import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/property.dart';
import '../repositories/property_repository.dart';

/// Resultado de geocoding: coordenadas + dirección canónica devuelta por OSM.
typedef GeocodeResult = ({LatLng coords, String canonicalAddress});

/// PropertyManagementService — agent operations (create, geocode).
///
/// Geocoding usa OSM Nominatim (free, 1 req/sec limit, sin API key).
///
/// addProperty delega al repository, que invalida cache local (Drift) y
/// sincroniza con Supabase. El caller (UI) debe invalidar
/// `propertiesProvider` para que `matchResultsProvider` recompute y
/// scoree la nueva propiedad con Groq automáticamente.
class PropertyManagementService {
  final PropertyRepository _repo;
  final Dio _dio;

  PropertyManagementService({
    required PropertyRepository repo,
    Dio? dio,
  })  : _repo = repo,
        _dio = dio ?? Dio();

  /// Geocodifica una dirección a coordenadas + nombre canónico usando OSM.
  /// Retorna null si no encuentra o si la red falla.
  ///
  /// Implementación: pide responseType plain para evitar deserialization
  /// quirks de Dio + parsea JSON manualmente. En Web el header User-Agent
  /// está prohibido por spec; el browser provee su propio User-Agent y
  /// Nominatim lo acepta. Limpia el char '#' que rompe URL encoding.
  Future<GeocodeResult?> geocodeAddress(String address) async {
    final cleaned = address.replaceAll('#', '').trim();
    final query = '$cleaned, Cochabamba, Bolivia';
    try {
      debugPrint('[Hito.Geocode] querying Nominatim for: "$query"');
      final response = await _dio.get<String>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'jsonv2',
          'limit': '1',
          'addressdetails': '1',
        },
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s >= 200 && s < 500,
        ),
      );
      if (response.statusCode != 200) {
        debugPrint(
          '[Hito.Geocode] HTTP ${response.statusCode}: ${response.data}',
        );
        return null;
      }
      final raw = response.data ?? '';
      if (raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) {
        debugPrint('[Hito.Geocode] empty results for "$cleaned"');
        return null;
      }
      final first = decoded.first as Map<String, dynamic>;
      final lat = double.parse(first['lat'].toString());
      final lng = double.parse(first['lon'].toString());
      final canonical = (first['display_name'] as String?) ?? cleaned;

      debugPrint('[Hito.Geocode] "$cleaned" → $lat,$lng | $canonical');
      return (
        coords: LatLng(lat, lng),
        canonicalAddress: canonical,
      );
    } catch (e, stack) {
      debugPrint('[Hito.Geocode] failed for "$cleaned": $e\n$stack');
      return null;
    }
  }

  /// Reverse geocoding — lat/lng → dirección canónica de OSM.
  /// Útil cuando el agente pone el pin directamente en el mapa.
  Future<GeocodeResult?> reverseGeocode(LatLng coords) async {
    try {
      debugPrint(
        '[Hito.Geocode] reverse for ${coords.latitude},${coords.longitude}',
      );
      final response = await _dio.get<String>(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': coords.latitude.toString(),
          'lon': coords.longitude.toString(),
          'format': 'jsonv2',
          'addressdetails': '1',
          'zoom': '18',
        },
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s >= 200 && s < 500,
        ),
      );
      if (response.statusCode != 200) {
        debugPrint('[Hito.Geocode] reverse HTTP ${response.statusCode}');
        return null;
      }
      final raw = response.data ?? '';
      if (raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final canonical = (decoded['display_name'] as String?) ?? '';
      if (canonical.isEmpty) return null;
      debugPrint('[Hito.Geocode] reverse → $canonical');
      return (coords: coords, canonicalAddress: canonical);
    } catch (e) {
      debugPrint('[Hito.Geocode] reverse failed: $e');
      return null;
    }
  }

  /// Inserta una nueva propiedad. El repo se encarga de Supabase + cache.
  Future<void> addProperty(Property property) async {
    debugPrint(
      '[Hito.PropertyMgmt] inserting id=${property.id} '
      'addr="${property.address}"',
    );
    await _repo.insert(property);
  }

  /// Generador de IDs únicos para nuevas propiedades creadas por agente.
  /// Formato: `agent-{timestamp_ms}-{random_3}`. Estable y único.
  static String newPropertyId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = (ts % 1000).toString().padLeft(3, '0');
    return 'agent-$ts-$rand';
  }
}
