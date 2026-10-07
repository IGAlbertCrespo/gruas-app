/// Parsea una fecha/hora que viene de Odoo.
///
/// Odoo serializa los Datetime como 'YYYY-MM-DD HH:MM:SS' en **UTC** pero sin
/// marca de zona. Si se parsea tal cual, Dart la interpreta como hora local y
/// `.toLocal()` no la convierte. Aquí la marcamos como UTC para que, al mostrar,
/// `.toLocal()` la pase correctamente a la hora del dispositivo.
DateTime? parseOdooDt(String? s) {
  if (s == null) return null;
  var v = s.trim();
  if (v.isEmpty || v.toLowerCase() == 'false') return null;
  if (!v.contains('T')) v = v.replaceFirst(' ', 'T');
  if (!v.endsWith('Z') && !v.contains('+')) v = '${v}Z';
  return DateTime.tryParse(v); // DateTime en UTC (isUtc = true)
}
