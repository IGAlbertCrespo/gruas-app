import 'dart:convert';
import 'dart:typed_data';

import 'package:secp256r1/secp256r1.dart';

import 'device_identity_service.dart';

/// Implementación de DeviceIdentityService con el plugin `secp256r1`
/// (clase nativa `SecureP256`): Keystore en Android, Secure Enclave en iOS.
///
/// Formatos (verificados contra el backend gruas_mobile_api, que los acepta):
///   - clave pública: punto crudo P-256 sin comprimir (0x04||X||Y, 65 bytes),
///     que es lo que devuelve `P256PublicKey.rawKey`.
///   - firma: r||s cruda (64 bytes), que es lo que devuelve `SecureP256.sign`.
/// Ambos se envían en base64.
class Secp256r1IdentityService implements DeviceIdentityService {
  @override
  Future<bool> hasKey({String alias = kDefaultKeyAlias}) async {
    // El plugin no expone "existe": getPublicKey crea la clave si no existe.
    // El alta efectiva la determina el device_id guardado en el almacén seguro,
    // no este método. Se mantiene por compatibilidad de la interfaz.
    try {
      final pk = await SecureP256.getPublicKey(alias);
      return pk.rawKey.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> getOrCreatePublicKey({String alias = kDefaultKeyAlias}) async {
    // Crea el par en hardware si no existe y devuelve la clave pública.
    final pk = await SecureP256.getPublicKey(alias);
    return base64Encode(pk.rawKey); // punto crudo de 65 bytes
  }

  @override
  Future<String> signNonce(String nonce, {String alias = kDefaultKeyAlias}) async {
    final payload = Uint8List.fromList(utf8.encode(nonce));
    final signature = await SecureP256.sign(alias, payload); // r||s cruda (64 bytes)
    return base64Encode(signature);
  }

  @override
  Future<void> deleteKey({String alias = kDefaultKeyAlias}) async {
    // El plugin `secp256r1` no expone borrado de clave. El re-emparejamiento se
    // resolverá por rotación de alias (pendiente). De momento es un no-op.
  }
}
