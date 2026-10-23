package org.moonfin.nativevideo

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri

/**
 * Arms [TlsPolicy] when the process starts, before Flutter does, so download
 * resumes and the car's artwork provider connect the same way the app would.
 * It serves no content.
 */
class MtlsInitProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        val context = context ?: return true
        TlsPolicy.setAllowUntrusted(
            context
                .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.pref_allow_self_signed_certs", false),
        )
        TlsPolicy.setClientCertificates(ClientCertificateVault.load(context))
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
