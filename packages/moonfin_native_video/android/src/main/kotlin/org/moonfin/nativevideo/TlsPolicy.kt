package org.moonfin.nativevideo

import android.util.Base64
import java.net.InetSocketAddress
import java.net.Socket
import java.security.KeyFactory
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.KeyManager
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509TrustManager

/**
 * Owns the process-wide HttpsURLConnection defaults, which media3, the
 * transmuxer, artwork and the download plugin all connect through.
 *
 * Two settings feed it: the self-signed opt-in, which media3 otherwise can't
 * see because it skips the Dart client, and the client certificates, each
 * presented only to the host it was imported for. The system defaults come
 * back once both are off.
 */
object TlsPolicy {
    data class ClientCertificate(val host: String, val chainPem: String, val keyPem: String)

    private class Identity(val key: PrivateKey, val chain: Array<X509Certificate>)

    private var allowUntrusted = false
    private var certificates: List<ClientCertificate> = emptyList()
    private var identities: Map<String, Identity> = emptyMap()
    private var systemSocketFactory: SSLSocketFactory? = null
    private var systemHostnameVerifier: HostnameVerifier? = null

    @Synchronized
    fun setAllowUntrusted(allow: Boolean) {
        if (allow == allowUntrusted) return
        allowUntrusted = allow
        install()
    }

    /** Returns false when [list] is what's already in place. */
    @Synchronized
    fun setClientCertificates(list: List<ClientCertificate>): Boolean {
        if (list == certificates) return false
        certificates = list
        identities = list.mapNotNull { c -> parse(c)?.let { c.host.lowercase() to it } }.toMap()
        install()
        return true
    }

    private fun install() {
        if (systemSocketFactory == null) {
            systemSocketFactory = HttpsURLConnection.getDefaultSSLSocketFactory()
            systemHostnameVerifier = HttpsURLConnection.getDefaultHostnameVerifier()
        }
        if (!allowUntrusted && identities.isEmpty()) {
            systemSocketFactory?.let { HttpsURLConnection.setDefaultSSLSocketFactory(it) }
            systemHostnameVerifier?.let { HttpsURLConnection.setDefaultHostnameVerifier(it) }
            return
        }
        val keyManagers = if (identities.isEmpty()) null else arrayOf<KeyManager>(HostKeyManager(identities))
        val trustManagers = if (allowUntrusted) arrayOf<TrustManager>(AcceptEveryCertificate) else null
        val context = SSLContext.getInstance("TLS").apply { init(keyManagers, trustManagers, null) }
        HttpsURLConnection.setDefaultSSLSocketFactory(context.socketFactory)
        if (allowUntrusted) {
            HttpsURLConnection.setDefaultHostnameVerifier { _, _ -> true }
        } else {
            systemHostnameVerifier?.let { HttpsURLConnection.setDefaultHostnameVerifier(it) }
        }
    }

    private fun parse(certificate: ClientCertificate): Identity? = try {
        val chain = CertificateFactory.getInstance("X.509")
            .generateCertificates(certificate.chainPem.byteInputStream())
            .map { it as X509Certificate }
            .toTypedArray()
        val keyDer = Base64.decode(
            certificate.keyPem.lines().filterNot { it.startsWith("-----") }.joinToString(""),
            Base64.DEFAULT,
        )
        val key = KeyFactory.getInstance(chain.first().publicKey.algorithm)
            .generatePrivate(PKCS8EncodedKeySpec(keyDer))
        Identity(key, chain)
    } catch (_: Exception) {
        null
    }

    private class HostKeyManager(
        private val identities: Map<String, Identity>,
    ) : X509ExtendedKeyManager() {
        override fun chooseClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out Principal>?,
            socket: Socket?,
        ): String? = alias(
            (socket as? SSLSocket)?.handshakeSession?.peerHost
                ?: (socket?.remoteSocketAddress as? InetSocketAddress)?.hostString,
        )

        override fun chooseEngineClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out Principal>?,
            engine: SSLEngine?,
        ): String? = alias(engine?.peerHost)

        private fun alias(host: String?): String? =
            host?.lowercase()?.takeIf { it in identities }

        override fun getCertificateChain(alias: String?): Array<X509Certificate>? =
            identities[alias]?.chain

        override fun getPrivateKey(alias: String?): PrivateKey? = identities[alias]?.key

        override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?): Array<String> =
            identities.keys.toTypedArray()

        override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?): Array<String>? = null

        override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?): String? = null
    }

    private object AcceptEveryCertificate : X509TrustManager {
        override fun checkClientTrusted(chain: Array<X509Certificate>?, authType: String?) = Unit

        override fun checkServerTrusted(chain: Array<X509Certificate>?, authType: String?) = Unit

        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }
}
