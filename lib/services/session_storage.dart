import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/client_profile.dart';

/// Persistencia ligera de estado de sesión entre reloads / app restarts.
///
/// **Por qué shared_preferences y no Drift**: estos campos son escalares y
/// pequeños (un bool, un enum, un JSON de profile <2KB). Drift sería overkill
/// y agrega latencia al cold start.
///
/// **Qué persiste**:
///   - `hasSelectedRole`: si el usuario ya pasó el role selector.
///   - `viewMode`: 'agent' o 'client' — controlado por el toggle del top bar.
///   - `clientProfile`: el último perfil generado por voz (JSON).
///
/// **Qué NO persiste** (intencional): `selectedPropertyId`, `activeFlow`,
/// `rightPanelView` — son estado UI efímero, no de sesión.
class SessionStorage {
  static const _kHasSelectedRole = 'hito.hasSelectedRole';
  static const _kViewMode = 'hito.viewMode';
  static const _kClientProfile = 'hito.clientProfile';

  final Future<SharedPreferences> _prefsFuture;

  SessionStorage({SharedPreferences? prefs})
      : _prefsFuture = prefs != null
            ? Future.value(prefs)
            : SharedPreferences.getInstance();

  Future<bool> getHasSelectedRole() async {
    final prefs = await _prefsFuture;
    return prefs.getBool(_kHasSelectedRole) ?? false;
  }

  Future<void> setHasSelectedRole(bool value) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_kHasSelectedRole, value);
  }

  /// Devuelve `'agent'` o `'client'` (default si no hay nada guardado).
  Future<String> getViewMode() async {
    final prefs = await _prefsFuture;
    return prefs.getString(_kViewMode) ?? 'client';
  }

  Future<void> setViewMode(String mode) async {
    final prefs = await _prefsFuture;
    await prefs.setString(_kViewMode, mode);
  }

  Future<ClientProfile?> getClientProfile() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_kClientProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ClientProfile.fromJson(json);
    } catch (e) {
      debugPrint('[Hito.Session] failed to decode profile: $e');
      // Borrar valor corrupto para no quedar en loop de fallo.
      await prefs.remove(_kClientProfile);
      return null;
    }
  }

  Future<void> setClientProfile(ClientProfile? profile) async {
    final prefs = await _prefsFuture;
    if (profile == null) {
      await prefs.remove(_kClientProfile);
      return;
    }
    await prefs.setString(_kClientProfile, jsonEncode(profile.toJson()));
  }

  /// Reset completo — útil para botón "salir de sesión" futuro.
  Future<void> clear() async {
    final prefs = await _prefsFuture;
    await Future.wait([
      prefs.remove(_kHasSelectedRole),
      prefs.remove(_kViewMode),
      prefs.remove(_kClientProfile),
    ]);
  }
}
