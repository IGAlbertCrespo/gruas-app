import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../maintenance_models.dart';
import '../maintenance_providers.dart';
import '../maintenance_repository.dart';

/// Formulario de parte de avería. Se abre desde la pestaña "Averías".
/// El catálogo ya viene cacheado (maintenanceCatalogProvider).
class MaintenanceReportScreen extends ConsumerStatefulWidget {
  const MaintenanceReportScreen({super.key, required this.catalog});
  final MaintenanceCatalog catalog;

  @override
  ConsumerState<MaintenanceReportScreen> createState() => _MaintenanceReportScreenState();
}

class _MaintenanceReportScreenState extends ConsumerState<MaintenanceReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _horasCtrl = TextEditingController();

  VehiculoTaller? _vehiculo;
  TipoAveria? _tipo;
  bool _inmoviliza = false;
  DateTime _fecha = DateTime.now();

  MaintenancePhoto? _photo;
  String? _photoName;
  bool _busy = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _kmCtrl.dispose();
    _horasCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      helpText: 'Fecha de detección',
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _addPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        // Comprimimos: el alta va en JSON (base64), no conviene mandar fotos enormes.
        maxWidth: 1600,
        imageQuality: 70,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _photo = MaintenancePhoto(filename: file.name, dataB64: base64Encode(bytes));
        _photoName = file.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo capturar la foto: $e')),
      );
    }
  }

  void _choosePhotoSource() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Hacer foto'),
              onTap: () {
                Navigator.pop(ctx);
                _addPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de la galería'),
              onTap: () {
                Navigator.pop(ctx);
                _addPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_vehiculo == null || _tipo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona vehículo y tipo de avería.')),
      );
      return;
    }
    // Capturamos antes de los await: tras el pop, este context ya no es válido.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final km = _kmCtrl.text.trim().isEmpty ? null : int.tryParse(_kmCtrl.text.trim());
      final horasTxt = _horasCtrl.text.trim().replaceAll(',', '.');
      final horasGrua = horasTxt.isEmpty ? null : double.tryParse(horasTxt);

      final res = await ref.read(maintenanceRepoProvider).create(
            vehicleId: _vehiculo!.id,
            tipoAveriaId: _tipo!.id,
            descripcion: _descCtrl.text.trim(),
            km: km,
            horasGrua: horasGrua,
            precisaInmovilizacion: widget.catalog.puedeInmovilizar && _inmoviliza,
            fechaDeteccion: _isoDate(_fecha),
            photos: _photo == null ? const [] : [_photo!],
          );

      final queued = res['queued'] == true;
      // Refrescamos el histórico al volver.
      ref.invalidate(maintenanceHistoryProvider);
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(queued
              ? 'Sin conexión: avería guardada. Se enviará al recuperar cobertura (sin foto).'
              : 'Avería registrada.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.catalog;
    return Scaffold(
      appBar: AppBar(title: const Text('Reportar avería')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<VehiculoTaller>(
                value: _vehiculo,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Vehículo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.local_shipping),
                ),
                items: [
                  for (final v in cat.vehiculos)
                    DropdownMenuItem(value: v, child: Text(v.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _vehiculo = v),
                validator: (v) => v == null ? 'Selecciona un vehículo' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<TipoAveria>(
                value: _tipo,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tipo de avería',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.build),
                ),
                items: [
                  for (final t in cat.tiposAveria)
                    DropdownMenuItem(value: t, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (t) => setState(() => _tipo = t),
                validator: (t) => t == null ? 'Selecciona el tipo' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  hintText: 'Qué le pasa al vehículo',
                  border: OutlineInputBorder(),
                ),
                validator: (s) =>
                    (s == null || s.trim().isEmpty) ? 'Describe la avería' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _kmCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Kilómetros (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.speed),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _horasCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,1}')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Horas de grúa (opcional)',
                  helperText: 'Lectura del horómetro',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
              ),
              const SizedBox(height: 16),
              // Fecha de detección (hoy por defecto).
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Fecha de detección'),
                subtitle: Text(_fmtDate(_fecha)),
                trailing: TextButton(onPressed: _pickDate, child: const Text('Cambiar')),
              ),
              // Inmovilización: solo si la empresa lo permite.
              if (cat.puedeInmovilizar)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Precisa inmovilización'),
                  subtitle: const Text('El vehículo no puede seguir circulando'),
                  value: _inmoviliza,
                  onChanged: (v) => setState(() => _inmoviliza = v),
                ),
              const SizedBox(height: 8),
              // Foto (solo se envía online).
              _PhotoField(
                name: _photoName,
                onAdd: _choosePhotoSource,
                onRemove: () => setState(() {
                  _photo = null;
                  _photoName = null;
                }),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_busy ? 'Enviando…' : 'Enviar parte'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoField extends StatelessWidget {
  const _PhotoField({required this.name, required this.onAdd, required this.onRemove});
  final String? name;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (name == null) {
      return OutlinedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Añadir foto (opcional)'),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.image, color: Colors.green),
        title: Text(name!, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: const Text('Se enviará solo con conexión'),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onRemove,
          tooltip: 'Quitar foto',
        ),
      ),
    );
  }
}