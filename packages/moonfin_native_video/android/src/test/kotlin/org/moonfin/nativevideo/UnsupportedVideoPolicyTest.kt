package org.moonfin.nativevideo

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UnsupportedVideoPolicyTest {

    private fun report(
        mediaType: String = "video",
        isPreview: Boolean = false,
        alreadyReported: Boolean = false,
        sourceHasVideo: Boolean = true,
        isReady: Boolean = false,
        hasVideoTrack: Boolean = true,
        videoSelected: Boolean = false,
    ): Boolean = shouldReportUnsupportedVideo(
        mediaType = mediaType,
        isPreview = isPreview,
        alreadyReported = alreadyReported,
        sourceHasVideo = sourceHasVideo,
        isReady = isReady,
        hasVideoTrack = hasVideoTrack,
        videoSelected = videoSelected,
    )

    @Test
    fun `a video track nothing selected is reported`() {
        assertTrue(report())
    }

    @Test
    fun `a selected video track is left alone`() {
        assertFalse(report(videoSelected = true))
    }

    @Test
    fun `no video track before the player is ready reports nothing`() {
        assertFalse(report(hasVideoTrack = false))
    }

    @Test
    fun `no video track once ready is reported when the server said there was video`() {
        assertTrue(report(hasVideoTrack = false, isReady = true))
    }

    @Test
    fun `no video track once ready stays quiet for a source without video`() {
        assertFalse(report(hasVideoTrack = false, isReady = true, sourceHasVideo = false))
    }

    @Test
    fun `a preview with no video track is never reported`() {
        assertFalse(report(hasVideoTrack = false, isReady = true, isPreview = true))
    }

    @Test
    fun `a second track change stays quiet`() {
        assertFalse(report(alreadyReported = true))
    }

    @Test
    fun `audio playback is never reported`() {
        assertFalse(report(mediaType = "audio"))
    }

    @Test
    fun `a preview is never reported`() {
        assertFalse(report(isPreview = true))
    }
}
