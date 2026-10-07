/// Reglas horarias de la APP, alineadas con el servidor
/// (gruas_mobile_api/controllers/tasks_api.py: _round_30, _normalizar_ventana).
///
/// Funciones puras, sin Flutter: testeables en test/horas_test.dart.
library;

/// Margen hacia el futuro que se acepta al elegir una hora. Nunca se informa a
/// futuro: dentro del margen se usa "ahora"; fuera, se entiende que es de ayer.
const Duration toleranciaFuturo = Duration(minutes: 15);

/// Ocurrencia pasada más reciente de [hora]:[minuto] respecto a [ahora].
///
/// - Hoy, si no es futura.
/// - Futura hasta [toleranciaFuturo] → [ahora].
/// - Futura más allá → ayer (p. ej. cierre de madrugada de un servicio nocturno).
///
/// "Ayer" se construye con `DateTime(y, m, d - 1, …)` y no con
/// `subtract(Duration(days: 1))`: así se respeta la hora de pared en los cambios
/// de horario (subtract resta 24 h exactas). Dart normaliza `d - 1` = 0 al
/// último día del mes anterior.
DateTime anclarAlPasado(int hora, int minuto, {DateTime? ahora}) {
  final now = ahora ?? DateTime.now();
  final hoy = DateTime(now.year, now.month, now.day, hora, minuto);
  if (!hoy.isAfter(now)) return hoy;
  if (hoy.difference(now) <= toleranciaFuturo) return now;
  return DateTime(now.year, now.month, now.day - 1, hora, minuto);
}

/// Réplica de `_round_30`: múltiplo de 30 min más cercano, empate hacia arriba.
/// 3h05 → 3.0 · 3h15 → 3.5 · 10h45 → 11.0.
double round30(double horas) =>
    horas <= 0 ? 0.0 : (horas * 2.0 + 0.5).floorToDouble() / 2.0;

/// Réplica de `_normalizar_ventana`: si fin <= inicio, el servicio cruzó la
/// medianoche y se suma un día (24 h, como el servidor).
DateTime normalizarFin(DateTime inicio, DateTime fin) =>
    fin.isAfter(inicio) ? fin : fin.add(const Duration(days: 1));

/// Horas brutas entre [inicio] y [fin], aplicando la regla de medianoche.
double horasEntre(DateTime inicio, DateTime fin) =>
    normalizarFin(inicio, fin).difference(inicio).inSeconds / 3600.0;

/// Facturable provisional (round30 − pausa, mínimo 0). SOLO para decidir si se
/// ofrece Mínimo/Incidencia; el importe real lo calcula el servidor.
double facturableProvisional(double horasBrutas, double pausa) {
  final f = round30(horasBrutas) - pausa;
  return f < 0 ? 0.0 : f;
}
/// Límites del selector de horas totales (modo duración). Por encima de 16 h el
/// servidor pide confirmación (422 duracion_sospechosa).
const double horasTotalesMin = 0.5;
const double horasTotalesMax = 24.0;

/// Valor inicial del selector de horas totales:
/// - tiempo transcurrido desde la apertura, redondeado a 30 min;
/// - si no hay apertura o aún no ha llegado (planificada), el servicio mínimo;
/// - si tampoco hay mínimo, 1 h.
double horasTotalesIniciales({DateTime? apertura, double minimo = 0, DateTime? ahora}) {
  final now = ahora ?? DateTime.now();
  final double v;
  if (apertura != null && now.isAfter(apertura)) {
    v = round30(now.difference(apertura).inSeconds / 3600.0);
  } else if (minimo > 0) {
    v = minimo;
  } else {
    v = 1.0;
  }
  return v.clamp(horasTotalesMin, horasTotalesMax).toDouble();
}
/// Regla de comida de compañía (CONTRATO §4.2).
enum ReglaComida { siempre, soloHorario, nunca }

ReglaComida reglaComidaDe(String? v) => switch (v) {
      'solo_horario' => ReglaComida.soloHorario,
      'nunca' => ReglaComida.nunca,
      _ => ReglaComida.siempre,
    };

/// Facturable provisional, modo horario: V − C (V = ventana round30). Con
/// `nunca`, la comida no descuenta. SOLO para decidir si se pregunta por incidencia.
double facturableHorario(DateTime inicio, DateTime fin, double comida, ReglaComida regla) {
  final c = regla == ReglaComida.nunca ? 0.0 : comida;
  final f = round30(horasEntre(inicio, fin)) - c;
  return f < 0 ? 0.0 : f;
}

/// Facturable provisional, modo horas totales: `siempre` H − C; resto H.
double facturableDuracion(double horas, double comida, ReglaComida regla) {
  final f = regla == ReglaComida.siempre ? horas - comida : horas;
  return f < 0 ? 0.0 : f;
}

/// Inicios/fines de comida posibles: :00 y :30 de reloj (hora local) dentro de
/// [inicio, fin], con el fin normalizado por medianoche.
List<DateTime> rejillaComida(DateTime inicio, DateTime fin) {
  final ini = inicio.toLocal();
  final f = normalizarFin(ini, fin.toLocal());
  var t = DateTime(ini.year, ini.month, ini.day, ini.hour, ini.minute >= 30 ? 30 : 0);
  if (t.isBefore(ini)) t = t.add(const Duration(minutes: 30));
  final out = <DateTime>[];
  while (!t.isAfter(f)) {
    out.add(t);
    t = t.add(const Duration(minutes: 30));
  }
  return out;
}

/// Índices (inicio, fin) por defecto en [rejilla] (length >= 2): inicio lo más
/// cerca de [minutoDefecto] (minutos desde 00:00, el día del inicio o del fin),
/// duración [pasos] × 30 min; ajustado a los extremos si cae fuera.
(int, int) franjaPorDefecto(List<DateTime> rejilla, int minutoDefecto, {int pasos = 2}) {
  final primero = rejilla.first;
  var mejor = 0;
  int? mejorDist;
  for (final dia in [primero, rejilla.last]) {
    final obj = DateTime(dia.year, dia.month, dia.day, minutoDefecto ~/ 60, minutoDefecto % 60);
    final idx = (obj.difference(primero).inMinutes / 30).round().clamp(0, rejilla.length - 1).toInt();
    final dist = rejilla[idx].difference(obj).inMinutes.abs();
    if (mejorDist == null || dist < mejorDist) {
      mejor = idx;
      mejorDist = dist;
    }
  }
  final ini = mejor.clamp(0, rejilla.length - 2).toInt();
  final fin = (ini + pasos).clamp(ini + 1, rejilla.length - 1).toInt();
  return (ini, fin);
}