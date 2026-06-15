import 'dart:math';

/// Identificador de idempotencia para operaciones offline.
///
/// Mismo esquema que ya usa asistencia (16 bytes aleatorios en hex), reutilizado
/// por la cola de averías para mantener consistencia. Al backend solo le importa
/// que sea único (columna `x_offline_uuid` con índice `UNIQUE`), no su formato.
String genOfflineUuid() {
  final r = Random();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}