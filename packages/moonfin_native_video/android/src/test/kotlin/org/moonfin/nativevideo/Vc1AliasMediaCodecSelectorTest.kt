package org.moonfin.nativevideo

import androidx.media3.common.MimeTypes
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class Vc1AliasMediaCodecSelectorTest {

    private fun decoder(name: String, mimeType: String, codecMimeType: String) =
        MediaCodecInfo.newInstance(
            name,
            mimeType,
            codecMimeType,
            null,
            true,
            false,
            true,
            false,
            false,
        )

    private fun selector(byMime: Map<String, List<MediaCodecInfo>>) =
        Vc1AliasMediaCodecSelector(
            MediaCodecSelector { mimeType, _, _ -> byMime[mimeType].orEmpty() },
        )

    @Test
    fun `a decoder listed as video VC1 is offered for VC-1 tracks`() {
        val mtk = decoder("c2.mtk.vc1.decoder", VC1_ALIAS_MIME, "video/VC1")
        val infos = selector(mapOf(VC1_ALIAS_MIME to listOf(mtk)))
            .getDecoderInfos(MimeTypes.VIDEO_VC1, false, false)

        assertEquals(1, infos.size)
        assertEquals("c2.mtk.vc1.decoder", infos[0].name)
        assertEquals(MimeTypes.VIDEO_VC1, infos[0].mimeType)
        assertEquals("video/VC1", infos[0].codecMimeType)
    }

    @Test
    fun `a standard VC-1 decoder wins over the alias`() {
        val standard = decoder("c2.vendor.wvc1.decoder", MimeTypes.VIDEO_VC1, "video/wvc1")
        val mtk = decoder("c2.mtk.vc1.decoder", VC1_ALIAS_MIME, "video/VC1")
        val standardList = listOf(standard)
        val infos = selector(
            mapOf(MimeTypes.VIDEO_VC1 to standardList, VC1_ALIAS_MIME to listOf(mtk)),
        ).getDecoderInfos(MimeTypes.VIDEO_VC1, false, false)

        assertSame(standardList, infos)
    }

    @Test
    fun `other types pass through untouched`() {
        val mtk = decoder("c2.mtk.vc1.decoder", VC1_ALIAS_MIME, "video/VC1")
        val infos = selector(mapOf(VC1_ALIAS_MIME to listOf(mtk)))
            .getDecoderInfos(MimeTypes.VIDEO_H264, false, false)

        assertEquals(0, infos.size)
    }
}
