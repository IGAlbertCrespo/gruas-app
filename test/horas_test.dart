import 'package:flutter_test/flutter_test.dart';
import 'package:gruas_app/shared/horas.dart';

void main() {
  group('anclarAlPasado', () {
    final ahora = DateTime(2026, 9, 28, 10, 0);

    test('hora pasada de hoy → hoy', () {
      expect(anclarAlPasado(9, 0, ahora: ahora), DateTime(2026, 9, 28, 9, 0));
    });

    test('futura dentro del margen (10 min) → ahora', () {
      expect(anclarAlPasado(10, 10, ahora: ahora), ahora);
    });

    test('futura en el límite exacto (15 min) → ahora', () {
      expect(anclarAlPasado(10, 15, ahora: ahora), ahora);
    });

    test('futura fuera del margen (20 min) → ayer', () {
      expect(anclarAlPasado(10, 20, ahora: ahora), DateTime(2026, 9, 27, 10, 20));
    });

    test('cierre de madrugada: a la 01:00 elige 23:30 → ayer 23:30', () {
      final madrugada = DateTime(2026, 9, 28, 1, 0);
      expect(anclarAlPasado(23, 30, ahora: madrugada), DateTime(2026, 9, 27, 23, 30));
    });

    test('día 1 de mes → último día del mes anterior', () {
      final dia1 = DateTime(2026, 10, 1, 0, 30);
      expect(anclarAlPasado(23, 0, ahora: dia1), DateTime(2026, 9, 30, 23, 0));
    });
  });

  group('round30 (réplica de _round_30)', () {
    test('ejemplos del servidor', () {
      expect(round30(10 + 31 / 60), 10.5);
      expect(round30(10 + 46 / 60), 11.0);
      expect(round30(10 + 15 / 60), 10.5); // empate hacia arriba
      expect(round30(10 + 45 / 60), 11.0); // empate hacia arriba
    });

    test('3h05 → 3.0 (la v1 calculaba 3.5 con ceil)', () {
      expect(round30(3 + 5 / 60), 3.0);
    });

    test('cero o negativo → 0', () {
      expect(round30(0), 0.0);
      expect(round30(-1), 0.0);
    });
  });

  group('ventana y facturable', () {
    test('cruce de medianoche: 22:00 → 02:00 = 4 h', () {
      final ini = DateTime(2026, 9, 27, 22, 0);
      final fin = DateTime(2026, 9, 27, 2, 0); // mismo día: el servidor suma 1 día
      expect(horasEntre(ini, fin), 4.0);
    });

    test('fin igual a inicio → 24 h', () {
      final t = DateTime(2026, 9, 27, 8, 0);
      expect(horasEntre(t, t), 24.0);
    });

    test('facturable = round30 − pausa', () {
      expect(facturableProvisional(3 + 5 / 60, 0.5), 2.5);
    });

    test('facturable nunca negativo', () {
      expect(facturableProvisional(0.5, 1.0), 0.0);
    });
  });
  group('horasTotalesIniciales', () {
    final ahora = DateTime(2026, 9, 28, 12, 0);

    test('desde la apertura, redondeado a 30 min (3h10 → 3 h)', () {
      expect(horasTotalesIniciales(apertura: DateTime(2026, 9, 28, 8, 50), ahora: ahora), 3.0);
    });

    test('apertura futura (planificada) → servicio mínimo', () {
      expect(horasTotalesIniciales(apertura: DateTime(2026, 9, 28, 13, 0), minimo: 4, ahora: ahora), 4.0);
    });

    test('recién iniciada (5 min) → 0,5 h, el mínimo del selector', () {
      expect(horasTotalesIniciales(apertura: DateTime(2026, 9, 28, 11, 55), ahora: ahora), 0.5);
    });

    test('sin apertura ni mínimo → 1 h', () {
      expect(horasTotalesIniciales(ahora: ahora), 1.0);
    });
  });
}