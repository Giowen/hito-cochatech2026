import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../models/property.dart';
import 'property_repository.dart';

/// AppwritePropertyRepository — repo real conectado a Appwrite Cloud.
///
/// Colección `properties` en la base `hito`. Permisos de colección abiertos
/// (Role.any en MVP, sin auth real). Para offline-first y fallback si la red
/// cae, se envuelve con `DriftCachedRepository` o `FallbackPropertyRepository`.
///
/// Mapeo clave vs Supabase:
///   - `Property.id` ↔ `$id` del documento (NO hay atributo `id` propio).
///   - Listas (`amenities`, `photos`, …) son atributos array nativos.
///   - `listDocuments` pagina de a 25 por defecto → pedimos `Query.limit(100)`.
class AppwritePropertyRepository implements PropertyRepository {
  final Databases _db;
  final String _databaseId;
  final String collectionId;

  AppwritePropertyRepository({
    required Databases databases,
    required String databaseId,
    this.collectionId = 'properties',
  })  : _db = databases,
        _databaseId = databaseId;

  @override
  Future<List<Property>> getAll() async {
    final res = await _db.listDocuments(
      databaseId: _databaseId,
      collectionId: collectionId,
      queries: [
        Query.equal('listing_status', 'activa'),
        Query.orderDesc('compatibility'),
        Query.limit(100),
      ],
    );
    return res.documents
        .map<Property>(_toProperty)
        .toList(growable: false);
  }

  @override
  Future<Property?> getById(String id) async {
    try {
      final doc = await _db.getDocument(
        databaseId: _databaseId,
        collectionId: collectionId,
        documentId: id,
      );
      return _toProperty(doc);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> insert(Property property) async {
    final data = property.toJson()..remove('id');
    data['listing_status'] = 'activa';
    await _db.createDocument(
      databaseId: _databaseId,
      collectionId: collectionId,
      documentId: property.id,
      data: data,
    );
  }

  /// Construye un `Property` desde un documento Appwrite: inyecta `$id` como
  /// `id` y normaliza numéricos (Appwrite devuelve null en atributos opcionales
  /// sin valor; `Property.fromJson` castea varios a `int` no-nullable).
  Property _toProperty(models.Document doc) {
    final data = Map<String, dynamic>.from(doc.data);
    data['id'] = doc.$id;
    return Property.fromJson(_normalize(data));
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> row) {
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return {
      ...row,
      'price_bob': asInt(row['price_bob']) ?? 0,
      'price_usd_paralelo': asInt(row['price_usd_paralelo']) ?? 0,
      'area_m2': asInt(row['area_m2']) ?? 0,
      'lot_m2': asInt(row['lot_m2']),
      'bedrooms': asInt(row['bedrooms']) ?? 0,
      'bathrooms': asInt(row['bathrooms']) ?? 0,
      'parking': asInt(row['parking']) ?? 0,
      'anticretico_bob': asInt(row['anticretico_bob']),
      'rent_monthly_bob': asInt(row['rent_monthly_bob']),
      'year_built': asInt(row['year_built']),
      'age_years': asInt(row['age_years']) ?? 0,
      'compatibility': asInt(row['compatibility']),
      'listed_days': asInt(row['listed_days']) ?? 0,
    };
  }
}
