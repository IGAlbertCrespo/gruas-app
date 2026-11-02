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
    final h = now.difference(apertura).inSeconds / 3600.0;
    v = h <= umbralOlvidoHoras ? round30(h) : 1.0; // más de 16 h: cierre olvidado

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
// ---------------------------------------------------------------------------
// v3.10 — redondeo parametrizable, facturable por formato y valores iniciales
// ---------------------------------------------------------------------------

/// v3.10 §4.6 — réplica del redondeo del servidor. Unidad U y tolerancia T en
/// minutos: base = múltiplo de U inferior; sube a la siguiente si
/// resto > 0 y resto >= T. Con U = 30 y T = 15 equivale a [round30].
double redondearFacturable(double horas, {int unidadMin = 30, int toleranciaMin = 15}) {
  if (horas <= 0) return 0.0;
  const eps = 1e-6; // minutos calculados desde fechas (segundos/3600*60)
  final u = unidadMin > 0 ? unidadMin : 30;
  final m = horas * 60.0;
  final base = ((m + eps) / u).floorToDouble() * u;
  final resto = m - base;
  final sube = resto > eps && resto >= toleranciaMin - eps;
  return (sube ? base + u : base) / 60.0;
}

/// v3.10 §4.2 — facturable provisional SOLO para decidir si se pregunta por
/// incidencia (el servidor es la autoridad). [bruto] = H en los formatos de horas
/// o la ventana V en inicio y fin; [comida] en horas. Redondeo una vez, al final.
double facturableTiempo(
  double bruto,
  double comida,
  ReglaComida regla, {
  required bool esInicioFin,
  int unidadMin = 30,
  int toleranciaMin = 15,
}) {
  final descuenta = regla == ReglaComida.siempre ||
      (regla == ReglaComida.soloHorario && esInicioFin);
  final f = descuenta ? bruto - comida : bruto;
  return redondearFacturable(f < 0 ? 0.0 : f,
      unidadMin: unidadMin, toleranciaMin: toleranciaMin);
}

/// Horas al múltiplo de [pasoMin] más cercano (tecleo y pasos del selector).
double ajustarHorasAPaso(double horas, int pasoMin) {
  final p = pasoMin > 0 ? pasoMin : 30;
  return (horas * 60.0 / p).roundToDouble() * p / 60.0;
}

/// Hora local ajustada hacia ATRÁS al paso (nunca queda en el futuro).
DateTime ajustarHoraAPaso(DateTime t, int pasoMin) {
  final p = pasoMin > 0 ? pasoMin : 30;
  final l = t.toLocal();
  final min = (l.hour * 60 + l.minute) ~/ p * p;
  return DateTime(l.year, l.month, l.day, min ~/ 60, min % 60);
}

/// v3.10 — valor inicial del selector de horas.
/// - Con inicio real (tarea iniciada en la APP) y reciente (≤ 16 h): el tiempo
///   transcurrido, ajustado al paso.
/// - Si no (solo horas o cierre olvidado): [previstas] (o 1 h).
/// Acotado a [paso, horasTotalesMax].
double horasInicialesV310({
  DateTime? inicioReal,
  double? previstas,
  int pasoMin = 30,
  DateTime? ahora,
}) {
  final now = ahora ?? DateTime.now();
  final paso = (pasoMin > 0 ? pasoMin : 30) / 60.0;
  double v;
  if (inicioReal != null && now.isAfter(inicioReal) &&
      horasDesde(inicioReal, ahora: now) <= umbralOlvidoHoras) {
    v = ajustarHorasAPaso(horasDesde(inicioReal, ahora: now), pasoMin);
  } else {
    v = ajustarHorasAPaso(previstas ?? 1.0, pasoMin);
  }
  return v.clamp(paso, horasTotalesMax).toDouble();
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
/// Por encima de estas horas desde el inicio se entiende cierre olvidado
/// (mismo umbral que `duracion_sospechosa` del servidor).
const double umbralOlvidoHoras = 16.0;

double horasDesde(DateTime inicio, {DateTime? ahora}) =>
    (ahora ?? DateTime.now()).difference(inicio).inSeconds / 3600.0;

/// Inicio de hace 16 h o menos: tienen sentido los atajos Ahora/30 min/1 h.
bool inicioReciente(DateTime inicio, {DateTime? ahora}) {
  final h = horasDesde(inicio, ahora: ahora);
  return h >= 0 && h <= umbralOlvidoHoras;
}

/// Fin = primera vez que [hora]:[minuto] (hora local) ocurre DESPUÉS de
/// [inicio]. Igual que `_normalizar_ventana` del servidor, pero anclado al día
/// de inicio y no al de hoy.
DateTime finTrasInicio(DateTime inicio, int hora, int minuto) {
  final ini = inicio.toLocal();
  final f = DateTime(ini.year, ini.month, ini.day, hora, minuto);
  return f.isAfter(ini) ? f : DateTime(ini.year, ini.month, ini.day + 1, hora, minuto);
}

/// Futuro más allá de [toleranciaFuturo].
bool esFuturo(DateTime d, {DateTime? ahora}) =>
    d.difference(ahora ?? DateTime.now()) > toleranciaFuturo;

/// Máximo de horas (múltiplo de 0,5 por defecto) desde [inicio] hasta ahora,
/// acotado a [horasTotalesMin]..[horasTotalesMax]: el fin nunca queda futuro.
double horasMaxHasta(DateTime inicio, {DateTime? ahora}) {
  final h = (horasDesde(inicio, ahora: ahora) * 2).floorToDouble() / 2;
  return h.clamp(horasTotalesMin, horasTotalesMax).toDouble();
}

DateTime soloDia(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

String _dos(int n) => n.toString().padLeft(2, '0');
const _diasSemana = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// "06/10"
String fmtDia(DateTime d) {
  final l = d.toLocal();
  return '${_dos(l.day)}/${_dos(l.month)}';
}

/// "lun 06/10 16:00" (sin intl: no requiere inicializar locales).
String fmtDiaHora(DateTime d) {
  final l = d.toLocal();
  return '${_diasSemana[l.weekday - 1]} ${fmtDia(l)} ${_dos(l.hour)}:${_dos(l.minute)}';
}