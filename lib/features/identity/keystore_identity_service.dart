import 'package:flutter/services.dart';

import 'device_identity_service.dart';

/// Implementación de DeviceIdentityService mediante un canal nativo propio
/// (Android Keystore P-256 en hardware, sin biometría). Ver MainActivity.kt.
///
/// Sustituye al difunto plugin `secp256r1`. iOS (Secure Enclave) se añadirá
/// con su propio canal cuando se compile en macOS; el backend ya acepta sus
/// formatos (punto crudo + firma DER).
class KeystoreIdentityService implements DeviceIdentityService {
  static const MethodChannel _channel =
      MethodChannel('com.infogest.gruas_app/crypto');

  @override
  Future<bool> hasKey({String alias = kDefaultKeyAlias}) async {
    final r = await _channel.invokeMethod<bool>('hasKey', {'alias': alias});
    return r ?? false;
  }

  @override
  Future<String> getOrCreatePublicKey({String alias = kDefaultKeyAlias}) async {
    final r = await _channel.invokeMethod<String>('getPublicKey', {'alias': alias});
    return r!; // clave pública SPKI DER en base64
  }

  @override
  Future<String> signNonce(String nonce, {String alias = kDefaultKeyAlias}) async {
    final r = await _channel.invokeMethod<String>(
      'sign',
      {'alias': alias, 'payload': nonce},
    );
    return r!; // firma DER en base64
  }

  @override
  Future<void> deleteKey({String alias = kDefaultKeyAlias}) async {
    await _channel.invokeMethod('deleteKey', {'alias': alias});
  }
}
