import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Helper que prefiere `String.fromEnvironment` (compile-time via
/// `--dart-define[-from-file]`) sobre `dotenv.env` (runtime via .env asset).
///
/// **Por qué este orden**:
///   - Para producción (Web/APK release): el deploy invoca
///     `flutter build web --dart-define=GROQ_API_KEY=... --dart-define=...`
///     y los valores quedan inlined en el bundle como const strings, sin
///     necesidad de empaquetar el .env como asset. La .env asset es un
///     leak: cualquier visitante del sitio puede descargar
///     `/assets/.env` desde DevTools.
///   - Para desarrollo local: si no se pasaron defines, cae al .env si
///     existe como asset. `dotenv.load()` se invoca en main.dart envuelto
///     en try/catch para que la app no crashee si el archivo no existe.
///
/// **Migración a producción**:
///   1. Quita `.env` del asset bundle en pubspec.yaml (ya hecho).
///   2. Pasá secrets en build: `flutter build web --dart-define-from-file=env.json`
///      donde env.json tiene `{"GROQ_API_KEY": "gsk_...", ...}` (gitignored).
///   3. Para .env asset legacy (dev only) el helper sigue funcionando.
class Env {
  Env._();

  /// Lee variable de entorno. Prioridad:
  /// 1. `String.fromEnvironment(key)` — inyectada en compile-time vía --dart-define.
  /// 2. `dotenv.env[key]` — cargada en runtime desde .env si está disponible.
  /// 3. `null` si nada está configurado.
  static String? get(String key) {
    // String.fromEnvironment defaultea a '' si no se pasó --dart-define=key=...
    // Tratamos '' como "no proporcionado" para no shadowar el dotenv.
    final fromDefine = _defineFor(key);
    if (fromDefine != null && fromDefine.isNotEmpty) return fromDefine;
    try {
      final value = dotenv.env[key];
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {
      // dotenv no fue inicializado — falla silenciosa para que prod no crashee.
    }
    return null;
  }

  /// Como `get` pero lanza si la variable no existe. Útil para keys obligatorias.
  static String require(String key) {
    final v = get(key);
    if (v == null || v.isEmpty) {
      throw StateError(
        'Missing required env "$key". Pass --dart-define=$key=... at build '
        'time, or include it in your local .env file.',
      );
    }
    return v;
  }

  /// `String.fromEnvironment` necesita keys literales, no se puede parametrizar
  /// dinámicamente. Switch manual para las keys que la app conoce.
  static String? _defineFor(String key) {
    switch (key) {
      case 'GROQ_API_KEY':
        const v = String.fromEnvironment('GROQ_API_KEY');
        return v.isEmpty ? null : v;
      case 'OPENROUTER_API_KEY':
        const v = String.fromEnvironment('OPENROUTER_API_KEY');
        return v.isEmpty ? null : v;
      case 'APPWRITE_ENDPOINT':
        const v = String.fromEnvironment('APPWRITE_ENDPOINT');
        return v.isEmpty ? null : v;
      case 'APPWRITE_PROJECT_ID':
        const v = String.fromEnvironment('APPWRITE_PROJECT_ID');
        return v.isEmpty ? null : v;
      case 'APPWRITE_DATABASE_ID':
        const v = String.fromEnvironment('APPWRITE_DATABASE_ID');
        return v.isEmpty ? null : v;
      case 'R2_ACCOUNT_ID':
        const v = String.fromEnvironment('R2_ACCOUNT_ID');
        return v.isEmpty ? null : v;
      case 'R2_BUCKET':
        const v = String.fromEnvironment('R2_BUCKET');
        return v.isEmpty ? null : v;
      case 'R2_ACCESS_KEY_ID':
        const v = String.fromEnvironment('R2_ACCESS_KEY_ID');
        return v.isEmpty ? null : v;
      case 'R2_SECRET_ACCESS_KEY':
        const v = String.fromEnvironment('R2_SECRET_ACCESS_KEY');
        return v.isEmpty ? null : v;
      case 'R2_PUBLIC_BASE_URL':
        const v = String.fromEnvironment('R2_PUBLIC_BASE_URL');
        return v.isEmpty ? null : v;
      default:
        return null;
    }
  }
}
