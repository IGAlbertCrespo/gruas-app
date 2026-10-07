import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../task_models.dart';

/// Sección DeCA del detalle de un servicio.
///
/// El ESTADO lo decide el servidor (`deca.estado`); aquí solo se pinta:
/// - vigente     → QR (dibujado en local: funciona sin cobertura) + "Ver DeCA".
/// - pendiente   → aviso: aún no emitido.
/// - anulado     → aviso: sin DeCA válido (la URL daría 404, no se muestra).
/// - externo     → lo emite el subcontratista (enlace si está registrado).
/// - no_requiere / sin bloque → no se muestra nada.
///
/// El QR codifica la misma URL pública que el QR del PDF: el inspector lo
/// escanea y descarga el PDF vigente desde su propio móvil.
class DecaSection extends StatelessWidget {
  const DecaSection({super.key, required this.deca, this.titulo});

  final Deca? deca;

  /// Texto bajo el QR a pantalla completa (p. ej. albarán o nombre del servicio).
  final String? titulo;
    // Mismo tamaño que el botón "Iniciar" del detalle.
  static final _compacto = FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    minimumSize: const Size(0, 36),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  static final _compactoOutlined = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    minimumSize: const Size(0, 36),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final d = deca;
    if (d == null || d.estado == 'no_requiere') return const SizedBox.shrink();

    final (color, etiqueta) = switch (d.estado) {
      'vigente' => (Colors.green, 'Vigente'),
      'pendiente' => (Colors.orange, 'Pendiente'),
      'anulado' => (Colors.red, 'Anulado'),
      'externo' => (Colors.blueGrey, 'Subcontratista'),
      _ => (Colors.grey, d.estado),
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.qr_code_2, color: color.shade700),
              const SizedBox(width: 8),
              const Text('DeCA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color.shade100, borderRadius: BorderRadius.circular(6)),
                child: Text(etiqueta,
                    style: TextStyle(fontWeight: FontWeight.bold, color: color.shade800)),
              ),
            ]),
            const SizedBox(height: 10),
            ..._cuerpo(context, d),
          ],
        ),
      ),
    );
  }

  List<Widget> _cuerpo(BuildContext context, Deca d) {
    switch (d.estado) {
      case 'vigente':
        final url = d.url!;
        return [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: _compacto,
                onPressed: () => _abrir(context, url),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Ver DeCA'),
              ),
              OutlinedButton.icon(
                style: _compactoOutlined,
                onPressed: () => _pantallaCompleta(context, url),
                icon: const Icon(Icons.qr_code_2, size: 18),
                label: const Text('Mostrar QR'),
              ),
            ],
          ),
        ];
      case 'pendiente':
        return const [
          Text('El DeCA aún no se ha emitido. Avisa a oficina antes de salir.'),
        ];
      case 'anulado':
        return const [
          Text('El DeCA de este servicio está anulado. No tiene documento válido.'),
        ];
      case 'externo':
        final ext = d.urlExterno;
        return [
          const Text('El DeCA lo emite el subcontratista.'),
          if (ext != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _abrir(context, ext),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Ver DeCA del subcontratista'),
            ),
          ],
        ];
      default:
        return const [];
    }
  }

  void _pantallaCompleta(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DecaQrScreen(url: url, titulo: titulo)),
    );
  }

  Future<void> _abrir(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el DeCA. Comprueba la cobertura.')),
      );
    }
  }
}

/// QR a pantalla completa, fondo blanco, para que el inspector lo escanee.
class DecaQrScreen extends StatelessWidget {
  const DecaQrScreen({super.key, required this.url, this.titulo});

  final String url;
  final String? titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('DeCA'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, c) {
            final lado = math.min(c.maxWidth, c.maxHeight) * 0.85;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    size: lado,
                    backgroundColor: Colors.white,
                  ),
                  if ((titulo ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(titulo!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, color: Colors.black87)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}