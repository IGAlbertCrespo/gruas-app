import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/env/environment.dart';
import 'shared/app_version.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppVersion.load();
  Env.config = const EnvConfig(
    environment: AppEnvironment.staging,
    defaultBaseUrl: '',
    allowEnvironmentSwitch: true, // switcher de entorno permitido en QA
  );
  runApp(const ProviderScope(child: GruasApp()));
}
