/// Abstracción de la identidad criptográfica del dispositivo.
///
/// Toda la app depende SOLO de esta interfaz. La implementación concreta
/// (Secure Enclave / Keystore vía un plugin) queda aislada, de modo que si
/// cambia el plugin o su API, solo se toca el adaptador.
///
/// Contrato criptográfico (debe casar con el backend gruas_mobile_api):
///   - Curva: P-256 (secp256r1).
///   - publicKeySpkiBase64: clave pública en SPKI DER, base64.
///   - sign(nonce): firma ECDSA/SHA-256 sobre los BYTES UTF-8 del nonce,
///                  resultado en DER, base64.
abstract class DeviceIdentityService {
  /// ¿Existe ya un par de claves para este perfil/alias?
  Future<bool> hasKey({String alias});

  /// Genera el par de claves en hardware (idempotente si ya existe).
  /// Devuelve la clave pública en SPKI DER base64.
  Future<String> getOrCreatePublicKey({String alias});

  /// Firma el nonce. Devuelve la firma DER en base64.
  Future<String> signNonce(String nonce, {String alias});

  /// Borra el par de claves (re-emparejamiento / baja del dispositivo).
  Future<void> deleteKey({String alias});
}

/// Alias por defecto. Con flavors distintos (staging/prod) el alias difiere,
/// de modo que cada entorno tiene su propio keypair y revocar es limpio.
const String kDefaultKeyAlias = 'gruas_device_key';
