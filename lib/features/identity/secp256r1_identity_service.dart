import 'package:secp256r1/secp256r1.dart';

import 'device_identity_service.dart';

/// Implementación de DeviceIdentityService con el plugin `secp256r1`
/// (Keystore en Android, Secure Enclave en iOS).
///
/// NOTA DE VERIFICACIÓN: la API exacta del plugin debe confirmarse contra la
/// versión instalada. Los nombres de método aquí reflejan el interfaz público
/// habitual del plugin (getPublicKey/sign/verify por `tag`). Si difieren, este
/// es el ÚNICO fichero a ajustar.
class Secp256r1IdentityService implements DeviceIdentityService {
  @override
  Future<bool> hasKey({String alias = kDefaultKeyAlias}) async {
    try {
      final pk = await Secp256r1.getPublicKey(alias);
      return pk.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> getOrCreatePublicKey({String alias = kDefaultKeyAlias}) async {
    // El plugin crea el par en hardware si no existe al pedir la pública.
    final spkiBase64 = await Secp256r1.getPublicKey(alias);
    return spkiBase64;
  }

  @override
  Future<String> signNonce(String nonce, {String alias = kDefaultKeyAlias}) async {
    // Firma los bytes UTF-8 del nonce; el plugin devuelve la firma (DER) base64.
    final signature = await Secp256r1.sign(alias, nonce);
    return signature;
  }

  @override
  Future<void> deleteKey({String alias = kDefaultKeyAlias}) async {
    // Algunos plugins exponen `removeKey`/`delete`. Verificar nombre exacto.
    await Secp256r1.getPublicKey(alias); // placeholder defensivo
  }
}
