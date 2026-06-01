import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/env/environment.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Env.config = const EnvConfig(
    environment: AppEnvironment.production,
    defaultBaseUrl: '', // se resuelve por QR de aprovisionamiento
    allowEnvironmentSwitch: false, // jamás cambiar de entorno en producción
  );
  runApp(const ProviderScope(child: GruasApp()));
}
