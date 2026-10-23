package org.moonfin.nativevideo

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.annotation.RequiresApi
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONObject

/**
 * Keeps the client certificates encrypted under an AndroidKeyStore key, for
 * work that connects before Flutter starts, like download resumes and the
 * car's artwork provider.
 */
object ClientCertificateVault {
    private const val KEY_ALIAS = "moonfin_client_certificates"
    private const val IV_LENGTH = 12

    fun save(context: Context, certificates: List<TlsPolicy.ClientCertificate>) {
        val file = file(context)
        if (certificates.isEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            file.delete()
            return
        }
        val json = JSONArray(
            certificates.map {
                JSONObject()
                    .put("host", it.host)
                    .put("chainPem", it.chainPem)
                    .put("keyPem", it.keyPem)
            },
        )
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        file.writeBytes(cipher.iv + cipher.doFinal(json.toString().toByteArray()))
    }

    fun load(context: Context): List<TlsPolicy.ClientCertificate> {
        val file = file(context)
        if (!file.exists() || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        return try {
            val bytes = file.readBytes()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, IV_LENGTH))
            val json = JSONArray(String(cipher.doFinal(bytes, IV_LENGTH, bytes.size - IV_LENGTH)))
            List(json.length()) { i ->
                val item = json.getJSONObject(i)
                TlsPolicy.ClientCertificate(
                    item.getString("host"),
                    item.getString("chainPem"),
                    item.getString("keyPem"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun file(context: Context) = File(context.noBackupFilesDir, "client_certificates.bin")

    @RequiresApi(Build.VERSION_CODES.M)
    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }
}
