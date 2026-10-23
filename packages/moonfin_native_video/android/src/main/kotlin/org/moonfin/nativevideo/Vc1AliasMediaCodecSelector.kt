package org.moonfin.nativevideo

import androidx.media3.common.MimeTypes
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector

internal const val VC1_ALIAS_MIME = "video/vc1"

/**
 * Media3 tags VC-1 tracks video/wvc1 and only matches decoders declared under
 * that name, so some MediaTek TVs that list their VC-1 decoder as video/VC1
 * never get to use it. When nothing answers to the standard name, this offers
 * the alias decoders under it. The codec is still configured with the type it
 * declared.
 */
internal class Vc1AliasMediaCodecSelector(
    private val delegate: MediaCodecSelector,
) : MediaCodecSelector {
    override fun getDecoderInfos(
        mimeType: String,
        requiresSecureDecoder: Boolean,
        requiresTunnelingDecoder: Boolean,
    ): List<MediaCodecInfo> {
        val infos = delegate.getDecoderInfos(
            mimeType,
            requiresSecureDecoder,
            requiresTunnelingDecoder,
        )
        if (infos.isNotEmpty() || mimeType != MimeTypes.VIDEO_VC1) return infos
        return delegate.getDecoderInfos(
            VC1_ALIAS_MIME,
            requiresSecureDecoder,
            requiresTunnelingDecoder,
        ).map { info ->
            MediaCodecInfo.newInstance(
                info.name,
                MimeTypes.VIDEO_VC1,
                info.codecMimeType,
                info.capabilities,
                info.hardwareAccelerated,
                info.softwareOnly,
                info.vendor,
                !info.adaptive,
                info.secure,
            )
        }
    }
}
