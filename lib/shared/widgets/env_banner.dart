import 'package:flutter/material.dart';
import '../../core/env/environment.dart';

/// Banda visible SOLO en staging, para que nadie confunda el entorno.
/// En producción no se muestra nada.
class EnvBanner extends StatelessWidget {
  const EnvBanner({super.key});
  @override
  Widget build(BuildContext context) {
    if (Env.config.isProduction) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.orange.shade800,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text('• ${Env.config.label} •',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}
