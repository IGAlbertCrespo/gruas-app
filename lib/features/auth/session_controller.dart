import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env/connection_profile.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/storage/secure_store.dart';
import 'session_models.dart';

/// Fases de la sesión que dirigen la navegación (router).
enum SessionPhase {
  loading,        // arrancando, leyendo almacenamiento
  needsProfile,   // sin perfil de conexión -> aprovisionar (QR)
  needsEnroll,    // con perfil, sin keypair aprobado -> enrolar
  pendingApproval,// enrolado, esperando aprobación del admin
  authenticated,  // token válido + perfil cargado
  revoked,        // dispositivo revocado
}

class SessionState {
  final SessionPhase phase;
  final OperatorProfile? profile;
  final String? message;

  const SessionState(this.phase, {this.profile, this.message});

  SessionState copyWith({SessionPhase? phase, OperatorProfile? profile, String? message}) =>
      SessionState(phase ?? this.phase, profile: profile ?? this.profile, message: message);
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this.ref) : super(const SessionState(SessionPhase.loading));
  final Ref ref;

  SecureStore get _store => ref.read(secureStoreProvider);

  /// Punto de entrada al abrir la app.
  Future<void> bootstrap() async {
    state = const SessionState(SessionPhase.loading);

    // 1. ¿Hay perfil de conexión?
    final encoded = await _store.readProfile();
    if (encoded == null) {
      state = const SessionState(SessionPhase.needsProfile);
      return;
    }
    ref.read(connectionProfileProvider.notifier).state = ConnectionProfile.decode(encoded);

    // 2. ¿Hay dispositivo enrolado?
    final deviceId = await _store.readDeviceId();
    if (deviceId == null) {
      state = const SessionState(SessionPhase.needsEnroll);
      return;
    }

    // 3. Intentar login (reto-respuesta) y cargar perfil.
    await _tryAuthenticate();
  }

  Future<void> _tryAuthenticate() async {
    try {
      final token = await ref.read(authRepositoryProvider).login();
      if (token == null) {
        state = const SessionState(SessionPhase.needsEnroll);
        return;
      }
      final profile = await ref.read(authRepositoryProvider).me();
      state = SessionState(SessionPhase.authenticated, profile: profile);
    } on ApiException catch (e) {
      if (e.deviceNotAuthorized) {
        // Enrolado pero aún no aprobado (o revocado).
        state = const SessionState(SessionPhase.pendingApproval);
      } else {
        state = SessionState(SessionPhase.needsEnroll, message: e.toString());
      }
    }
  }

  /// Guarda el perfil escaneado por QR y avanza a enrolamiento.
  Future<void> setProfileFromQr(ConnectionProfile profile) async {
    await _store.saveProfile(profile.encode());
    ref.read(connectionProfileProvider.notifier).state = profile;
    state = const SessionState(SessionPhase.needsEnroll);
  }

  /// Lanza el enrolamiento (genera keypair + envía pública).
  Future<void> enroll({String? deviceName}) async {
    try {
      final st = await ref.read(authRepositoryProvider).enroll(name: deviceName, platform: 'flutter');
      state = st == EnrollmentState.approved
          ? const SessionState(SessionPhase.loading)
          : const SessionState(SessionPhase.pendingApproval);
      if (st == EnrollmentState.approved) await _tryAuthenticate();
    } on ApiException catch (e) {
      state = SessionState(SessionPhase.needsEnroll, message: e.toString());
    }
  }

  /// Reintenta autenticar (botón "Ya me han aprobado").
  Future<void> retry() => _tryAuthenticate();

  /// Re-emparejamiento total: borra token, perfil y keypair.
  Future<void> resetPairing() async {
    await ref.read(identityProvider).deleteKey();
    await _store.wipe();
    state = const SessionState(SessionPhase.needsProfile);
  }
}

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) => SessionController(ref));
