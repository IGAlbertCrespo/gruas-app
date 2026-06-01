import 'dart:convert';

/// Perfil de conexión: a qué Odoo/BD apunta este dispositivo.
/// Se resuelve en el aprovisionamiento (QR) y se persiste en almacenamiento seguro.
///
/// Multi-cliente (A vs B) = perfiles distintos resueltos al dar de alta.
/// Cambiar de cliente/entorno = re-emparejar (no migrar datos).
class ConnectionProfile {
  final String baseUrl; // p.ej. https://clienteA.odoo.midominio.com
  final String db;      // base de datos Odoo
  final String? label;  // nombre legible para el usuario

  const ConnectionProfile({
    required this.baseUrl,
    required this.db,
    this.label,
  });

  Map<String, dynamic> toJson() => {'base_url': baseUrl, 'db': db, 'label': label};

  factory ConnectionProfile.fromJson(Map<String, dynamic> j) => ConnectionProfile(
        baseUrl: j['base_url'] as String,
        db: j['db'] as String,
        label: j['label'] as String?,
      );

  String encode() => jsonEncode(toJson());
  static ConnectionProfile decode(String s) =>
      ConnectionProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
