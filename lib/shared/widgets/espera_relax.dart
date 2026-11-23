import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// v3.13 — Capa de espera a pantalla completa.
///
/// Un gancho de grúa que se balancea despacio, como un péndulo, con un halo que
/// "respira" detrás y frases tranquilas que se van turnando. Tapa la pantalla de
/// debajo (no se ve el detalle ni se puede pulsar nada) y bloquea el botón atrás.
///
/// Sin dependencias: CustomPainter + dos AnimationController. Con "reducir
/// movimiento" del sistema (MediaQuery.disableAnimations) el gancho queda quieto.
///
/// Uso típico, como última capa de un Stack:
/// ```dart
/// Stack(children: [
///   scaffoldNormal,
///   if (_esperando) const Positioned.fill(child: EsperaRelax()),
/// ])
/// ```
class EsperaRelax extends StatefulWidget {
  const EsperaRelax({
    super.key,
    this.mensajes = const [
      'Guardando las horas…',
      'Preparando el albarán…',
      'Un momento, ya casi está…',
    ],
  });

  final List<String> mensajes;

  @override
  State<EsperaRelax> createState() => _EsperaRelaxState();
}

class _EsperaRelaxState extends State<EsperaRelax> with TickerProviderStateMixin {
  /// Ida y vuelta del péndulo: 3,2 s por lado (lento, sin tirones).
  late final AnimationController _pendulo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat(reverse: true);

  /// Respiración del halo: 4 s por fase (inspirar / espirar).
  late final AnimationController _respira = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  )..repeat(reverse: true);

  /// Fundido de entrada para que la capa no aparezca de golpe.
  late final AnimationController _entrada = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();

  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    if (widget.mensajes.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
        if (mounted) setState(() => _i++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pendulo.dispose();
    _respira.dispose();
    _entrada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final quieto = MediaQuery.of(context).disableAnimations;
    final texto = widget.mensajes.isEmpty ? '' : widget.mensajes[_i % widget.mensajes.length];

    return PopScope(
      canPop: false,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _entrada, curve: Curves.easeOut),
        child: Material(
          color: cs.surface,
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 200,
                    height: 230,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_pendulo, _respira]),
                      builder: (_, __) {
                        // ±11° con aceleración senoidal: se frena en los extremos.
                        final angulo = quieto
                            ? 0.0
                            : (Curves.easeInOutSine.transform(_pendulo.value) * 2 - 1) * 0.19;
                        final halo = quieto
                            ? 1.0
                            : 0.86 + 0.18 * Curves.easeInOut.transform(_respira.value);
                        return CustomPaint(
                          painter: _GanchoPainter(
                            angulo: angulo,
                            halo: halo,
                            linea: cs.primary,
                            fondo: cs.primaryContainer,
                            estructura: cs.outlineVariant,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 700),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: Text(
                      texto,
                      key: ValueKey(_i),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pluma horizontal arriba, carro, cable, motón y gancho en "J".
/// Todo lo que cuelga se dibuja en vertical y se gira [angulo] sobre el carro.
class _GanchoPainter extends CustomPainter {
  _GanchoPainter({
    required this.angulo,
    required this.halo,
    required this.linea,
    required this.fondo,
    required this.estructura,
  });

  final double angulo;
  final double halo;
  final Color linea;
  final Color fondo;
  final Color estructura;

  static const double _cable = 120;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const yPluma = 14.0;

    final trazo = Paint()
      ..color = linea
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Pluma: dos cordones y una celosía suave.
    final pluma = Paint()
      ..color = estructura
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(12, yPluma - 6), Offset(size.width - 12, yPluma - 6), pluma);
    canvas.drawLine(Offset(12, yPluma + 2), Offset(size.width - 12, yPluma + 2), pluma);
    for (var x = 12.0; x < size.width - 20; x += 16) {
      canvas.drawLine(Offset(x, yPluma + 2), Offset(x + 8, yPluma - 6), pluma);
      canvas.drawLine(Offset(x + 8, yPluma - 6), Offset(x + 16, yPluma + 2), pluma);
    }

    // Carro sobre la pluma.
    final carro = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, yPluma + 6), width: 22, height: 10),
      const Radius.circular(3),
    );
    canvas.drawRRect(carro, Paint()..color = linea);

    // Lo que cuelga, girado sobre el carro.
    canvas.save();
    canvas.translate(cx, yPluma + 11);
    canvas.rotate(-angulo);

    // Halo que respira, detrás del gancho.
    final centroHalo = const Offset(0, _cable + 22);
    canvas.drawCircle(
      centroHalo,
      38 * halo,
      Paint()
        ..shader = RadialGradient(
          colors: [fondo.withOpacity(0.85), fondo.withOpacity(0.0)],
        ).createShader(Rect.fromCircle(center: centroHalo, radius: 38 * halo)),
    );

    // Cable.
    canvas.drawLine(Offset.zero, const Offset(0, _cable), trazo..strokeWidth = 2);

    // Motón (bloque del gancho).
    final moton = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, _cable + 6), width: 20, height: 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(moton, Paint()..color = linea);

    // Gancho en "J": vástago y curva abierta hacia la izquierda.
    trazo.strokeWidth = 3.5;
    const r = 10.0;
    const centro = Offset(0, _cable + 34);
    canvas.drawLine(const Offset(0, _cable + 14), Offset(r, centro.dy), trazo);
    canvas.drawArc(
      Rect.fromCircle(center: centro, radius: r),
      0,
      math.pi * 1.3,
      false,
      trazo,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GanchoPainter old) =>
      old.angulo != angulo || old.halo != halo || old.linea != linea || old.fondo != fondo;
}