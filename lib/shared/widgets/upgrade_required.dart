import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env/environment.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';

final _urlInDetail = RegExp(
  r'https?://[^\s<>"]+|/gruas/app/download[^\s<>"]*',
  caseSensitive: false,
);

/// La 426 no trae clave `url`: el enlace va dentro de `detail`.
Uri downloadUri({required String? detail, required String? baseUrl}) {
  final match = detail == null ? null : _urlInDetail.firstMatch(detail)?.group(0);
  late final Uri uri;
  if (match != null && match.toLowerCase().startsWith('http')) {
    uri = Uri.parse(match);
  } else {
    final path = (match == null || match.isEmpty) ? '/gruas/app/download' : match;
    final base = (baseUrl ?? '').replaceFirst(RegExp(r'/$'), '');
    uri = Uri.parse('$base$path');
  }
  if (Env.config.isProduction) return uri;
  final q = Map<String, String>.from(uri.queryParameters);
  q.putIfAbsent('flavor', () => 'staging');
  return uri.replace(queryParameters: q);
}

Future<bool> showUpgradeIfNeeded(BuildContext context, Object error) async {
  if (error is! ApiException || !error.upgradeRequired) return false;
  if (!context.mounted) return true;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpgradeRequiredDialog(error: error),
  );
  return true;
}

class UpgradeRequiredDialog extends ConsumerWidget {
  const UpgradeRequiredDialog({super.key, required this.error});
  final ApiException error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Hay que actualizar la app'),
      content: Text(error.detail ?? 'Esta versión ya no es válida para tu empresa.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        FilledButton.icon(
          onPressed: () => _openDownload(ref),
          icon: const Icon(Icons.download),
          label: const Text('Descargar'),
        ),
      ],
    );
  }

  Future<void> _openDownload(WidgetRef ref) async {
    final uri = downloadUri(
      detail: error.detail,
      baseUrl: ref.read(connectionProfileProvider)?.baseUrl,
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class UpgradeRequiredView extends ConsumerWidget {
  const UpgradeRequiredView({super.key, required this.error});
  final ApiException error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.system_update, size: 48),
          const SizedBox(height: 16),
          Text(
            error.detail ?? 'Hay que actualizar la app para seguir con las tareas.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final uri = downloadUri(
                detail: error.detail,
                baseUrl: ref.read(connectionProfileProvider)?.baseUrl,
              );
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.download),
            label: const Text('Descargar'),
          ),
        ],
      ),
    );
  }
}
/// Muestra el error de una acción: diálogo de actualización si es 426, SnackBar
/// en otro caso. Centraliza el patrón y evita usar `context` tras un `await`
/// en los call sites (lint use_build_context_synchronously).
Future<void> mostrarErrorAccion(BuildContext context, Object error, {String prefijo = ''}) async {
  if (await showUpgradeIfNeeded(context, error)) return;
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$prefijo$error')));
}
