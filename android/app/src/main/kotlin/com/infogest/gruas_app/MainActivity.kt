package com.infogest.gruas_app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Canal nativo de identidad criptográfica del dispositivo.
 *
 * Genera y custodia un par de claves ECDSA P-256 en el Android Keystore
 * (respaldo hardware / TEE), SIN exigir autenticación de usuario (sin biometría).
 * La clave privada NO es exportable.
 *
 * Formatos que entrega (los acepta el backend gruas_mobile_api):
 *   - clave pública: X.509 SubjectPublicKeyInfo (SPKI DER), en base64
 *   - firma: ECDSA DER (SHA256withECDSA), en base64
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.infogest.gruas_app/crypto"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getPublicKey" ->
                            result.success(getPublicKey(call.argument<String>("alias")!!))
                        "sign" ->
                            result.success(
                                sign(
                                    call.argument<String>("alias")!!,
                                    call.argument<String>("payload")!!,
                                )
                            )
                        "hasKey" ->
                            result.success(hasKey(call.argument<String>("alias")!!))
                        "deleteKey" -> {
                            deleteKey(call.argument<String>("alias")!!)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("CRYPTO_ERROR", e.message, null)
                }
            }
    }

    private fun keyStore(): KeyStore =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    /** Devuelve la clave pública (SPKI DER, base64), creando el par si no existe. */
    private fun getPublicKey(alias: String): String {
        val ks = keyStore()
        if (!ks.containsAlias(alias)) {
            val kpg = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore"
            )
            kpg.initialize(
                KeyGenParameterSpec.Builder(
                    alias,
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
                )
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setUserAuthenticationRequired(false) // sin biometría
                    .build()
            )
            kpg.generateKeyPair()
        }
        val encoded = ks.getCertificate(alias).publicKey.encoded // SPKI DER
        return Base64.encodeToString(encoded, Base64.NO_WRAP)
    }

    /** Firma los BYTES UTF-8 del payload (el nonce). Devuelve firma DER en base64. */
    private fun sign(alias: String, payloadUtf8: String): String {
        val ks = keyStore()
        val privateKey = ks.getKey(alias, null) as PrivateKey
        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(privateKey)
        signer.update(payloadUtf8.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(signer.sign(), Base64.NO_WRAP)
    }

    private fun hasKey(alias: String): Boolean = keyStore().containsAlias(alias)

    private fun deleteKey(alias: String) = keyStore().deleteEntry(alias)
}
