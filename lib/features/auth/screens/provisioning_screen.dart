import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/env/connection_profile.dart';
import '../session_controller.dart';

/// Aprovisionamiento: se escanea el QR {url, db} generado en Odoo, o se
/// introduce manualmente (cámara no disponible, emulador, QR ilegible).
class ProvisioningScreen extends ConsumerStatefulWidget {
  const ProvisioningScreen({super.key});
  @override
  ConsumerState<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends ConsumerState<ProvisioningScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _apply(ConnectionProfile profile) {
    if (_handled) return;
    _handled = true;
    ref.read(sessionControllerProvider.notifier).setProfileFromQr(profile);
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled) return;
    final raw = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _apply(ConnectionProfile(
        baseUrl: j['url'] as String,
        db: j['db'] as String,
        label: j['label'] as String?,
      ));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR no válido')),
      );
    }
  }

  Future<void> _manualEntry() async {
    final profile = await showModalBottomSheet<ConnectionProfile>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ManualEntrySheet(),
    );
    if (profile != null) _apply(profile);
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
          Expanded(
            child: MobileScanner(
              controller: _scanner,
              onDetect: _onDetect,
              // Si la cámara falla, mostramos el motivo en vez de pantalla negra.
              errorBuilder: (context, error, child) => _CameraError(
                error: error,
                onManual: _manualEntry,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: _manualEntry,
                icon: const Icon(Icons.keyboard),
                label: const Text('Introducir manualmente'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onManual});
  final MobileScannerException error;
  final VoidCallback onManual;
  @override
  Widget build(BuildContext context) {
    final code = error.errorCode;
    final msg = switch (code) {
      MobileScannerErrorCode.permissionDenied =>
        'Permiso de cámara denegado. Concédelo en Ajustes del teléfono.',
      MobileScannerErrorCode.unsupported =>
        'Este dispositivo no soporta la cámara para escanear.',
      _ => 'No se pudo iniciar la cámara (${code.name}).\n${error.errorDetails?.message ?? ''}',
    };
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.no_photography, color: Colors.white70, size: 48),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onManual,
            icon: const Icon(Icons.keyboard),
            label: const Text('Introducir manualmente'),
          ),
        ],
      ),
    );
  }
}

class _ManualEntrySheet extends StatefulWidget {
  const _ManualEntrySheet();
  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  final _url = TextEditingController(text: 'https://');
  final _db = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _db.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    final db = _db.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _error = 'La URL debe empezar por http:// o https://');
      return;
    }
    if (db.isEmpty) {
      setState(() => _error = 'Indica la base de datos.');
      return;
    }
    Navigator.pop(context, ConnectionProfile(baseUrl: url, db: db));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Conexión manual',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Pídele al administrador la URL del servidor y la base de datos.',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'URL del servidor',
              hintText: 'https://miempresa.odoo.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _db,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Base de datos', hintText: 'nombre-bd'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.check), label: const Text('Conectar')),
        ],
      ),
    );
  }
}
