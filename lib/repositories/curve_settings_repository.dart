import 'package:hive_flutter/hive_flutter.dart';

import '../features/home/logic/curve_logic.dart';
import '../models/curve_settings.dart';

/// Repository per la persistenza di [CurveSettings] su Hive.
/// Sostituisce le 8+ chiamate sparse ad [AppStorage] nei metodi
/// di stato relativi alle impostazioni curva.
class CurveSettingsRepository {
  static const String _box = 'clima_sense_box';

  /// Carica le impostazioni correnti da Hive.
  /// Restituisce [CurveSettings.defaults()] se il box è vuoto.
  CurveSettings load() {
    final box = Hive.box(_box);
    final modeStr = box.get('systemMode', defaultValue: 'heating') as String;
    final heatIso = box.get('lastAiApplyHeating') as String?;
    final coolIso = box.get('lastAiApplyCooling') as String?;

    return CurveSettings(
      heatingSlope: (box.get('heatingSlope', defaultValue: 1.2) as num).toDouble(),
      heatingOffset: (box.get('heatingOffset', defaultValue: 0.0) as num).toDouble(),
      coolingSlope: (box.get('coolingSlope', defaultValue: 0.5) as num).toDouble(),
      coolingOffset: (box.get('coolingOffset', defaultValue: 0.0) as num).toDouble(),
      mode: modeStr == 'cooling' ? SystemMode.cooling : SystemMode.heating,
      lastAiApplyHeating: heatIso != null ? DateTime.tryParse(heatIso) : null,
      lastAiApplyCooling: coolIso != null ? DateTime.tryParse(coolIso) : null,
    );
  }

  /// Persiste l'intero oggetto [CurveSettings] su Hive in un'unica operazione.
  Future<void> save(CurveSettings s) async {
    final box = Hive.box(_box);
    await box.putAll({
      'heatingSlope': s.heatingSlope,
      'heatingOffset': s.heatingOffset,
      'coolingSlope': s.coolingSlope,
      'coolingOffset': s.coolingOffset,
      'systemMode': s.mode == SystemMode.cooling ? 'cooling' : 'heating',
    });

    if (s.lastAiApplyHeating != null) {
      await box.put('lastAiApplyHeating', s.lastAiApplyHeating!.toIso8601String());
    } else {
      await box.delete('lastAiApplyHeating');
    }

    if (s.lastAiApplyCooling != null) {
      await box.put('lastAiApplyCooling', s.lastAiApplyCooling!.toIso8601String());
    } else {
      await box.delete('lastAiApplyCooling');
    }
  }

  /// Reset completo ai valori di fabbrica.
  Future<void> reset() => save(CurveSettings.defaults());
}
