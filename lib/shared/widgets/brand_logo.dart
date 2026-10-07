import 'package:flutter/material.dart';

/// Ruta del logo. Coloca tu PNG (fondo transparente) en esta ruta y decláralo
/// en pubspec.yaml bajo "flutter:":
///   assets:
///     - assets/images/logo.png
/// Hasta entonces, se muestra un distintivo provisional (no rompe el build).
const String kLogoAsset = 'assets/images/logo.png';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 96, this.opacity = 1, this.fallbackColor});
  final double size;
  final double opacity;
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final color = fallbackColor ?? Theme.of(context).colorScheme.primary;
    return Opacity(
      opacity: opacity,
      child: Image.asset(
        kLogoAsset,
        height: size,
        fit: BoxFit.contain,
        // Si el asset aún no está colocado/declarado, no peta: muestra el icono.
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.25)),
          child: Icon(Icons.local_shipping, size: size * 0.55, color: Colors.white),
        ),
      ),
    );
  }
}
