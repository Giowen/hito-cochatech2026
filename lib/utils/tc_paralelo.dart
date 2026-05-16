/// Tipo de cambio paralelo USD/Bs — crítico en Bolivia 2025-2026.
/// El TC oficial está fijo en ~6.96 pero el mercado paralelo opera 12-15 Bs/USD.
/// Valuaciones inmobiliarias sin esto son ficción (anchor del Acto 2).
class TcParalelo {
  /// Tasa paralela asumida para demo y valuaciones hardcoded.
  /// Aligned con claude-design canonical data (12.20 Bs/USD).
  static const double rate = 12.20;

  /// Tasa oficial BCB (referencia, no usada en valuaciones reales).
  static const double oficial = 6.96;

  /// Convierte BOB → USD paralelo.
  static int bobToUsd(int bob) => (bob / rate).round();

  /// Convierte USD paralelo → BOB.
  static int usdToBob(int usd) => (usd * rate).round();
}
