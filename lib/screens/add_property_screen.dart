import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../models/property.dart';
import '../providers.dart';
import '../services/property_management_service.dart';
import '../theme.dart';
import '../utils/tc_paralelo.dart';

/// AddPropertyScreen — form para que el agente añada una propiedad.
/// Layout: 2 columnas en >900px, 1 columna en mobile. Diseño en cards
/// alineado con el resto de la app (HitoTokens + Geist + Instrument Serif).
class AddPropertyScreen extends ConsumerStatefulWidget {
  const AddPropertyScreen({super.key});

  @override
  ConsumerState<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends ConsumerState<AddPropertyScreen> {
  final _formKey = GlobalKey<FormState>();

  final _address = TextEditingController();
  final _title = TextEditingController();
  final _priceUsd = TextEditingController();
  final _bedrooms = TextEditingController(text: '3');
  final _bathrooms = TextEditingController(text: '2');
  final _parking = TextEditingController(text: '1');
  final _areaM2 = TextEditingController(text: '180');
  final _lotM2 = TextEditingController();
  final _yearBuilt = TextEditingController();
  final _description = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  final _mapController = MapController();
  static const _cochabambaCenter = LatLng(-17.39, -66.16);
  LatLng? _pinCoords;

  String? _canonicalAddress;
  String _type = 'casa';
  String _listingMode = 'venta';
  final Set<String> _supportedTransactions = {'venta'};
  bool _hasLien = false;
  bool _geocoding = false;
  bool _submitting = false;
  String? _submitError;
  String? _geocodeError;

  bool get _hasCoords =>
      _latCtrl.text.trim().isNotEmpty && _lngCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _address.dispose();
    _title.dispose();
    _priceUsd.dispose();
    _bedrooms.dispose();
    _bathrooms.dispose();
    _parking.dispose();
    _areaM2.dispose();
    _lotM2.dispose();
    _yearBuilt.dispose();
    _description.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _geocode() async {
    if (_address.text.trim().isEmpty) {
      setState(() {
        _geocodeError = 'Escribe una dirección primero.';
      });
      return;
    }
    setState(() {
      _geocoding = true;
      _geocodeError = null;
      _submitError = null;
    });
    final service = ref.read(propertyManagementServiceProvider);
    final result = await service.geocodeAddress(_address.text.trim());
    if (!mounted) return;
    setState(() {
      _geocoding = false;
      if (result != null) {
        _canonicalAddress = result.canonicalAddress;
        _pinCoords = result.coords;
        _latCtrl.text = result.coords.latitude.toStringAsFixed(6);
        _lngCtrl.text = result.coords.longitude.toStringAsFixed(6);
        _geocodeError = null;
        _mapController.move(result.coords, 16);
      } else {
        _canonicalAddress = null;
        _geocodeError =
            'No se pudo geocodificar. Mueve el pin manualmente en el mapa.';
      }
    });
  }

  Future<void> _onMapTap(LatLng coords) async {
    setState(() {
      _pinCoords = coords;
      _latCtrl.text = coords.latitude.toStringAsFixed(6);
      _lngCtrl.text = coords.longitude.toStringAsFixed(6);
      _geocoding = true;
      _geocodeError = null;
    });

    final service = ref.read(propertyManagementServiceProvider);
    final result = await service.reverseGeocode(coords);
    if (!mounted) return;
    setState(() {
      _geocoding = false;
      if (result != null) {
        _canonicalAddress = result.canonicalAddress;
        // SIEMPRE sobrescribe el address con la dirección del pin actual.
        // Si el usuario quería conservar lo que escribió antes, edita después.
        final parts = result.canonicalAddress.split(',');
        _address.text = parts.take(3).join(',').trim();
      } else {
        _canonicalAddress = null;
        _geocodeError =
            'No se pudo obtener la dirección del pin. Editá manualmente.';
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) {
      setState(() {
        _submitError =
            'Necesitamos coordenadas válidas. Geocodifica o ajusta manualmente.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final priceUsd = int.tryParse(_priceUsd.text.trim()) ?? 0;
    final property = Property(
      id: PropertyManagementService.newPropertyId(),
      address: _address.text.trim(),
      lat: lat,
      lng: lng,
      priceBob: TcParalelo.usdToBob(priceUsd),
      priceUsdParalelo: priceUsd,
      areaM2: int.tryParse(_areaM2.text.trim()) ?? 0,
      bedrooms: int.tryParse(_bedrooms.text.trim()) ?? 0,
      bathrooms: int.tryParse(_bathrooms.text.trim()) ?? 0,
      type: _type,
      listingMode: _listingMode,
      amenities: const [],
      ageYears: _yearBuilt.text.trim().isEmpty
          ? 0
          : (DateTime.now().year - int.parse(_yearBuilt.text.trim()))
              .clamp(0, 200),
      photos: const [],
      cochabambaTags: const [],
      listingStatus: 'activa',
      description: _description.text.trim(),
      hasLien: _hasLien,
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      parking: int.tryParse(_parking.text.trim()) ?? 0,
      lotM2: int.tryParse(_lotM2.text.trim()),
      supportedTransactions: _supportedTransactions.toList(),
      yearBuilt: int.tryParse(_yearBuilt.text.trim()),
      listedDays: 0,
      agentName: 'María Quiroga',
    );

    try {
      final service = ref.read(propertyManagementServiceProvider);
      await service.addProperty(property);
      ref.invalidate(propertiesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: HitoTokens.success,
          content: Text(
            'Propiedad creada. La IA está calculando compatibilidad...',
            style: GoogleFonts.geist(color: Colors.white),
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = 'Error guardando: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HitoTokens.bone,
      appBar: AppBar(
        backgroundColor: HitoTokens.bone,
        foregroundColor: HitoTokens.ink1,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Nueva propiedad',
          style: GoogleFonts.instrumentSerif(
            fontSize: 24,
            color: HitoTokens.ink1,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final maxWidth = wide ? 1000.0 : double.infinity;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                  child: wide
                      ? _wideLayout()
                      : _narrowLayout(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _wideLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _locationCard(),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _priceAndSurfaceCard()),
            const SizedBox(width: 14),
            Expanded(child: _characteristicsCard()),
          ],
        ),
        const SizedBox(height: 14),
        _transactionCard(),
        const SizedBox(height: 14),
        _descriptionCard(),
        if (_submitError != null) ...[
          const SizedBox(height: 12),
          _errorBanner(_submitError!),
        ],
        const SizedBox(height: 18),
        _submitButton(),
      ],
    );
  }

  Widget _narrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _locationCard(),
        const SizedBox(height: 14),
        _priceAndSurfaceCard(),
        const SizedBox(height: 14),
        _characteristicsCard(),
        const SizedBox(height: 14),
        _transactionCard(),
        const SizedBox(height: 14),
        _descriptionCard(),
        if (_submitError != null) ...[
          const SizedBox(height: 12),
          _errorBanner(_submitError!),
        ],
        const SizedBox(height: 18),
        _submitButton(),
      ],
    );
  }

  // ── Cards ──────────────────────────────────────────────────────────────

  Widget _locationCard() {
    return _Card(
      title: 'UBICACIÓN',
      icon: Icons.location_on_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Map picker — el flujo principal. Tap pone el pin + reverse geocode.
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Text(
              _pinCoords == null
                  ? 'Toca en el mapa para marcar la propiedad'
                  : 'Toca de nuevo para mover el pin',
              style: GoogleFonts.geist(
                fontSize: 11,
                color: HitoTokens.ink3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
            child: SizedBox(
              height: 260,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _pinCoords ?? _cochabambaCenter,
                      initialZoom: _pinCoords != null ? 16 : 13,
                      onTap: (_, point) => _onMapTap(point),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.hito.app',
                      ),
                      if (_pinCoords != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _pinCoords!,
                              width: 40,
                              height: 40,
                              alignment: Alignment.topCenter,
                              child: Icon(
                                Icons.location_on,
                                size: 36,
                                color: HitoTokens.teal,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (_geocoding)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(HitoTokens.rXl),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.1),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'OSM...',
                              style: GoogleFonts.geist(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_canonicalAddress != null) ...[
            const SizedBox(height: 8),
            _confirmBanner(_canonicalAddress!),
          ],
          if (_geocodeError != null) ...[
            const SizedBox(height: 8),
            _errorBanner(_geocodeError!),
          ],
          const SizedBox(height: 12),
          _textField(
            controller: _address,
            label: 'Dirección',
            hint: 'Av. Pando 1500, Cala Cala',
            required: true,
            onChanged: (_) {
              if (_canonicalAddress != null) {
                setState(() => _canonicalAddress = null);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _geocoding ? null : _geocode,
                style: TextButton.styleFrom(
                  foregroundColor: HitoTokens.teal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.travel_explore_outlined, size: 14),
                label: Text(
                  'Buscar esta dirección en el mapa',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _latCtrl,
                  label: 'Latitud',
                  hint: '-17.395',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: (v) {
                    final lat = double.tryParse(v.trim());
                    final lng = double.tryParse(_lngCtrl.text.trim());
                    if (lat != null && lng != null) {
                      setState(() => _pinCoords = LatLng(lat, lng));
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _textField(
                  controller: _lngCtrl,
                  label: 'Longitud',
                  hint: '-66.158',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: (v) {
                    final lat = double.tryParse(_latCtrl.text.trim());
                    final lng = double.tryParse(v.trim());
                    if (lat != null && lng != null) {
                      setState(() => _pinCoords = LatLng(lat, lng));
                    }
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 0, left: 4, bottom: 8),
            child: Text(
              _hasCoords
                  ? 'Pin colocado. Puedes ajustar la dirección manualmente '
                      'si OSM no acertó.'
                  : 'Toca en el mapa, o escribe la dirección y "buscar".',
              style: GoogleFonts.geist(
                fontSize: 10,
                color: HitoTokens.ink3,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          _textField(
            controller: _title,
            label: 'Título (opcional)',
            hint: 'Casa familiar — Av. Pando',
          ),
        ],
      ),
    );
  }

  Widget _priceAndSurfaceCard() {
    return _Card(
      title: 'PRECIO Y SUPERFICIE',
      icon: Icons.straighten_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _textField(
            controller: _priceUsd,
            label: 'Precio (USD paralelo)',
            hint: '215000',
            required: true,
            keyboardType: TextInputType.number,
            prefix: '\$',
          ),
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _areaM2,
                  label: 'Área construida',
                  required: true,
                  keyboardType: TextInputType.number,
                  suffix: 'm²',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _textField(
                  controller: _lotM2,
                  label: 'Terreno',
                  keyboardType: TextInputType.number,
                  suffix: 'm²',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _characteristicsCard() {
    return _Card(
      title: 'CARACTERÍSTICAS',
      icon: Icons.king_bed_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _bedrooms,
                  label: 'Dormitorios',
                  required: true,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _textField(
                  controller: _bathrooms,
                  label: 'Baños',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _textField(
                  controller: _parking,
                  label: 'Parqueos',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          _textField(
            controller: _yearBuilt,
            label: 'Año de construcción (opcional)',
            hint: '2018',
            keyboardType: TextInputType.number,
          ),
          Row(
            children: [
              Expanded(
                child: _dropdown(
                  label: 'Tipo',
                  value: _type,
                  options: const ['casa', 'departamento', 'terreno'],
                  onChanged: (v) => setState(() => _type = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transactionCard() {
    return _Card(
      title: 'MODALIDAD',
      icon: Icons.handshake_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dropdown(
            label: 'Modalidad principal',
            value: _listingMode,
            options: const ['venta', 'alquiler', 'anticretico'],
            onChanged: (v) {
              setState(() {
                _listingMode = v;
                _supportedTransactions.add(v);
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              'Modalidades soportadas:',
              style: GoogleFonts.geist(
                fontSize: 11,
                color: HitoTokens.ink3,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final t in ['venta', 'alquiler', 'anticretico'])
                FilterChip(
                  label: Text(
                    t,
                    style: GoogleFonts.geist(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  selected: _supportedTransactions.contains(t),
                  onSelected: (sel) {
                    setState(() {
                      if (sel) {
                        _supportedTransactions.add(t);
                      } else if (t != _listingMode) {
                        _supportedTransactions.remove(t);
                      }
                    });
                  },
                  selectedColor: HitoTokens.teal.withAlpha(40),
                  checkmarkColor: HitoTokens.teal,
                  side: BorderSide(color: HitoTokens.border),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _descriptionCard() {
    return _Card(
      title: 'OTROS',
      icon: Icons.notes_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _textField(
            controller: _description,
            label: 'Descripción (opcional)',
            hint: 'Casa con patio, vigilancia 24h, cerca de colegios...',
            maxLines: 3,
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: _hasLien
                  ? HitoTokens.dangerBg
                  : HitoTokens.paper2,
              borderRadius: BorderRadius.circular(HitoTokens.rMd),
              border: Border.all(
                color: _hasLien
                    ? HitoTokens.danger.withAlpha(120)
                    : HitoTokens.border,
              ),
            ),
            child: CheckboxListTile(
              value: _hasLien,
              onChanged: (v) => setState(() => _hasLien = v ?? false),
              activeColor: HitoTokens.danger,
              title: Text(
                'La propiedad tiene gravamen activo',
                style: GoogleFonts.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Si marcas esta opción, el análisis legal mostrará alerta '
                'de hipoteca con detalles del registro.',
                style: GoogleFonts.geist(
                  fontSize: 11,
                  color: HitoTokens.ink3,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Widget _confirmBanner(String canonical) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: HitoTokens.successBg,
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: HitoTokens.success.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: HitoTokens.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'OSM: $canonical',
              style: GoogleFonts.geist(
                fontSize: 11,
                color: HitoTokens.success,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: HitoTokens.dangerBg,
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: HitoTokens.danger.withAlpha(120)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: HitoTokens.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.geist(
                fontSize: 11,
                color: HitoTokens.danger,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitButton() {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _submitting ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: HitoTokens.teal,
        ),
        icon: _submitting
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check_rounded, size: 18),
        label: Text(
          _submitting
              ? 'Guardando + AI scoring...'
              : 'Crear propiedad',
          style: GoogleFonts.geist(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool required = false,
    int? maxLines = 1,
    TextInputType? keyboardType,
    String? prefix,
    String? suffix,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
        style: GoogleFonts.geist(fontSize: 13, color: HitoTokens.ink1),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.geist(
            fontSize: 12,
            color: HitoTokens.ink3,
          ),
          hintText: hint,
          hintStyle: GoogleFonts.geist(
            fontSize: 12,
            color: HitoTokens.ink4,
          ),
          prefixText: prefix,
          suffixText: suffix,
          filled: true,
          fillColor: HitoTokens.paper,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
            borderSide: BorderSide(color: HitoTokens.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
            borderSide: BorderSide(color: HitoTokens.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
            borderSide: BorderSide(color: HitoTokens.teal, width: 1.5),
          ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        validator: required
            ? (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null
            : null,
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        style: GoogleFonts.geist(fontSize: 13, color: HitoTokens.ink1),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.geist(
            fontSize: 12,
            color: HitoTokens.ink3,
          ),
          filled: true,
          fillColor: HitoTokens.paper,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
            borderSide: BorderSide(color: HitoTokens.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
            borderSide: BorderSide(color: HitoTokens.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
            borderSide: BorderSide(color: HitoTokens.teal, width: 1.5),
          ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        items: [
          for (final o in options)
            DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _Card({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: HitoTokens.paper,
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: HitoTokens.teal),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.geist(
                  fontSize: 11,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                  color: HitoTokens.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
