import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/environment.dart';
import '../../../core/providers.dart';

/// Nombre comercial de la app (marca). Cámbialo aquí si quieres otro.
const String kAppCommercialName = 'Gru@s 360';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(connectionProfileProvider);
    final empresa = profile?.label; // nombre de empresa (del perfil conectado)
    final entorno = Env.config.label; // PRODUCCIÓN / STAGING

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // ---- LOGO ----
              // Provisional: distintivo con icono. Para usar tu logo real:
              //   1) copia el fichero a assets/images/logo.png
              //   2) en pubspec.yaml, bajo "flutter:", añade:
              //        assets:
              //          - assets/images/logo.png
              //   3) sustituye este Container por:
              //        Image.asset('assets/images/logo.png', height: 96)
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.local_shipping, size: 54, color: Colors.white),
              ),
              const SizedBox(height: 20),

              // ---- NOMBRE COMERCIAL ----
              Text(
                kAppCommercialName,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: scheme.primary),
              ),

              // ---- EMPRESA ----
              if (empresa != null && empresa.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(empresa, style: const TextStyle(fontSize: 16, color: Colors.black87)),
              ],

              // ---- ENTORNO (no la BD) ----
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (Env.config.isProduction ? Colors.green : Colors.orange).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  entorno,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Env.config.isProduction ? Colors.green.shade800 : Colors.orange.shade900,
                  ),
                ),
              ),

              const Spacer(),
              const CircularProgressIndicator(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
