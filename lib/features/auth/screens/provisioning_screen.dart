import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/env/connection_profile.dart';
import '../session_controller.dart';

/// Aprovisionamiento: se escanea el QR generado en Odoo con {base_url, db}.
/// Resuelve a qué cliente/entorno se conecta el dispositivo.
class ProvisioningScreen extends ConsumerStatefulWidget {
  const ProvisioningScreen({super.key});
  @override
  ConsumerState<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends ConsumerState<ProvisioningScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture cap) {
    if (_handled) return;
    final raw = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final profile = ConnectionProfile(
        baseUrl: j['url'] as String,
        db: j['db'] as String,
        label: j['label'] as String?,
      );
      _handled = true;
      ref.read(sessionControllerProvider.notifier).setProfileFromQr(profile);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR no válido')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar conexión')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Escanea el código QR de alta que te facilite el administrador.',
                textAlign: TextAlign.center),
          ),
          Expanded(child: MobileScanner(onDetect: _onDetect)),
        ],
      ),
    );
  }
}
