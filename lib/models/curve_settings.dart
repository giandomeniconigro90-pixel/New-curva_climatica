import '../features/home/logic/curve_logic.dart';

/// Value Object immutabile che raccoglie tutti i parametri
/// di calibrazione della curva climatica.
class CurveSettings {
  final double heatingSlope;
  final double heatingOffset;
  final double coolingSlope;
  final double coolingOffset;
  final SystemMode mode;
  final DateTime? lastAiApplyHeating;
  final DateTime? lastAiApplyCooling;

  const CurveSettings({
    required this.heatingSlope,
    required this.heatingOffset,
    required this.coolingSlope,
    required this.coolingOffset,
    required this.mode,
    this.lastAiApplyHeating,
    this.lastAiApplyCooling,
  });

  /// Valori di default al primo avvio.
  /// heatingSlope 1.0 ottimizzato per casa X-LAM con fan coil e VMC+recuperatore.
  factory CurveSettings.defaults() => const CurveSettings(
        heatingSlope: 1.0,
        heatingOffset: 0.0,
        coolingSlope: 0.5,
        coolingOffset: 0.0,
        mode: SystemMode.heating,
      );

  /// Pendenza attiva in base alla modalità corrente
  double get activeSlope =>
      mode == SystemMode.heating ? heatingSlope : coolingSlope;

  /// Offset attivo in base alla modalità corrente
  double get activeOffset =>
      mode == SystemMode.heating ? heatingOffset : coolingOffset;

  CurveSettings copyWith({
    double? heatingSlope,
    double? heatingOffset,
    double? coolingSlope,
    double? coolingOffset,
    SystemMode? mode,
    DateTime? lastAiApplyHeating,
    DateTime? lastAiApplyCooling,
    bool clearLastAiApplyHeating = false,
    bool clearLastAiApplyCooling = false,
  }) {
    return CurveSettings(
      heatingSlope: heatingSlope ?? this.heatingSlope,
      heatingOffset: heatingOffset ?? this.heatingOffset,
      coolingSlope: coolingSlope ?? this.coolingSlope,
      coolingOffset: coolingOffset ?? this.coolingOffset,
      mode: mode ?? this.mode,
      lastAiApplyHeating: clearLastAiApplyHeating
          ? null
          : (lastAiApplyHeating ?? this.lastAiApplyHeating),
      lastAiApplyCooling: clearLastAiApplyCooling
          ? null
          : (lastAiApplyCooling ?? this.lastAiApplyCooling),
    );
  }
}
